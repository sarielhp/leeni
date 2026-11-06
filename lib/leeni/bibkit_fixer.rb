# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bibkit_fixer.rb
#
# Bibkit::Compare decides when two blocks say the same thing. Bibkit::Fixer
# plans what a local .bib file needs from a collection (missing entries with
# their crossref/xdata parents, the @string definitions and @preamble blocks
# they use) and renders the new file text. It writes nothing.
#
# Conflicting candidates: the first is added; unless it comes from a
# preferred source, every other variant is added under the key
# <key>_leeni_alt_<n> after a marker comment. A real entry is needed because
# BibTeX parses entries even inside @comment{...}; the marker has no '@',
# which BibTeX would take as the start of an entry.
# ==============================================================================

require_relative 'bibkit_collection'

module Bibkit
  ALT_TAG = '_leeni_alt_'
  ALT_KEY = /^[ \t]*@[ \t]*[A-Za-z][\w-]*[ \t]*[{(][ \t]*([^,\s{}()=]+_leeni_alt_\d+)/
  BLOCK_PREFIX = /\A@\s*[A-Za-z][\w-]*\s*[{(]\s*/
  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].to_set.freeze

  # [[key, line], ...] of the unresolved alternatives in a .bib text (keys
  # of entries, or names of @string macros).
  def self.alternatives_in(text)
    text = text.b
    found = []
    text.scan(ALT_KEY) { found << [Regexp.last_match(1), text[0...Regexp.last_match.begin(0)].count("\n") + 1] }
    found
  end

  module Compare
    IGNORED = %w[file timestamp owner abstract annote annotation keywords date-added date-modified].freeze

    def self.same?(first, second) = signature(first) == signature(second)

    def self.signature(item)
      fields = item.fields.reject { |f| ignored?(f.name) }.map { |f| [Bibkit.fold(f.name), comparable(f.value)] }
      [Bibkit.fold(item.type), fields.sort]
    end

    # True when `rich` says everything `poor` says (same type, every compared
    # field present with the same value), so `poor` adds nothing.
    def self.covers?(rich, poor)
      rich_type, rich_fields = signature(rich)
      poor_type, poor_fields = signature(poor)
      rich_type == poor_type && (poor_fields - rich_fields).empty?
    end

    # Ties and braces are typography, not content: P.~Lindstrom is
    # P. Lindstrom and {Voronoi} is Voronoi for comparison.
    def self.comparable(value)
      normalize(value).tr('~{}', ' ').gsub(/\s+/, ' ').strip
    end

    def self.ignored?(name)
      return false unless name

      folded = Bibkit.fold(name)
      IGNORED.include?(folded) || folded.start_with?('bdsk-')
    end

    def self.normalize(value)
      text = value.b.gsub(/\s+/, ' ').strip
      inner = text[1...-1]
      wrapped = text.length >= 2 && balanced?(inner) &&
                ((text.start_with?('{') && text.end_with?('}')) || (text.start_with?('"') && text.end_with?('"')))
      wrapped ? inner.strip : text
    end

    def self.balanced?(text)
      depth = 0
      text.each_char do |ch|
        depth += { '{' => 1, '}' => -1 }.fetch(ch, 0)
        return false if depth.negative?
      end
      depth.zero?
    end
  end

  # hit: the Hit added live; alternatives: other distinct Hits for the key.
  Addition = Struct.new(:hit, :alternatives) do
    def hits = [hit] + alternatives
    def key = hit.item.key
  end

  # entries and strings: Additions; preambles: Hits; not_found and
  # unknown_macros: names; case_hints: key => keys differing only in case.
  class Plan
    attr_reader :entries, :strings, :preambles, :not_found, :case_hints, :unknown_macros

    def initialize
      @entries = []
      @strings = []
      @preambles = []
      @not_found = []
      @case_hints = {}
      @unknown_macros = []
    end

    def empty? = entries.empty? && strings.empty? && preambles.empty?
    def conflicts = (entries + strings).reject { |a| a.alternatives.empty? }
  end

  class Fixer
    # local_files: the BibFiles the paper already uses.
    def initialize(local_files, collection)
      @local = local_files
      @collection = collection
    end

    def plan(missing_keys:, undefined_macros: [])
      @plan = Plan.new
      plan_entries(missing_keys)
      plan_strings(undefined_macros.map { |m| Bibkit.fold(m) })
      plan_preambles
      @plan
    end

    # The target file's text with the plan applied: @preamble and @string
    # blocks first (BibTeX needs a macro defined before its first use),
    # entries appended.
    def render(text, plan)
      head = plan.preambles.map { |hit| hit.item.text.b } + ordered(plan.strings).flat_map { |a| blocks_for(a) }
      tail = plan.entries.flat_map { |a| blocks_for(a) }
      out = +''.b
      out << "% Added by leeni --bib-fix\n" << head.join("\n") << "\n\n" unless head.empty?
      out << text.b
      out << "\n" unless out.empty? || out.end_with?("\n")
      out << "\n" << tail.join("\n\n") << "\n" unless tail.empty?
      out
    end

    private

    def plan_entries(keys)
      queue = keys.map(&:to_s)
      seen = Set.new
      until queue.empty?
        key = queue.shift
        next if !seen.add?(key.b) || local_entry?(key)

        addition = find_entry(key)
        next unless addition

        @plan.entries << addition
        queue.concat(addition.hits.flat_map { |h| parent_keys(h.item) })
      end
    end

    def find_entry(key)
      hits = @collection.entries_for(key)
      return choose(hits) unless hits.empty?

      similar = @collection.entries_like(key).map { |h| h.item.key }.uniq
      if similar.empty?
        @plan.not_found << key
      else
        @plan.case_hints[key] = similar
      end
      nil
    end

    # Distinct variants, intact ones before ones with recorded problems; a
    # winner from a preferred source drops the rest. A variant another one
    # covers is no conflict: the richer one stands in its place.
    def choose(hits)
      return Addition.new(hits.first, []) if hits.first.preferred

      variants = hits.uniq { |h| Compare.signature(h.item) }
      variants = variants.map { |v| variants.find { |r| !r.equal?(v) && Compare.covers?(r.item, v.item) } || v }.uniq
      variants = variants.each_with_index.sort_by { |h, i| [h.item.problems.empty? ? 0 : 1, i] }.map(&:first)
      Addition.new(variants.first, variants.drop(1))
    end

    def parent_keys(item)
      %w[crossref xdata].flat_map do |name|
        field = item.field(name)
        field ? Compare.normalize(field.value).split(',').map(&:strip).reject(&:empty?) : []
      end
    end

    def plan_strings(undefined)
      queue = (@plan.entries.flat_map { |a| a.hits.flat_map { |h| h.item.macros } } + undefined).uniq
      seen = Set.new
      until queue.empty?
        name = queue.shift
        next if MONTHS.include?(name) || !seen.add?(name) || local_macros.include?(name)

        hits = @collection.strings_for(name)
        if hits.empty?
          @plan.unknown_macros << name
          next
        end

        addition = choose(hits)
        @plan.strings << addition
        queue.concat(addition.hits.flat_map { |h| h.item.macros })
      end
    end

    def plan_preambles
      items = (@plan.entries + @plan.strings).flat_map { |a| a.hits.map(&:item) }
      queue = items.flat_map(&:commands).map(&:b).uniq
      seen = Set.new
      added = Set.new
      until queue.empty?
        command = queue.shift
        next if !seen.add?(command) || local_commands.include?(command)

        hit = @collection.preambles_defining(command).first
        next unless hit && added.add?(hit.item.object_id)

        @plan.preambles << hit
        queue.concat(hit.item.commands.map(&:b))
      end
    end

    # A @string must follow the strings it is built from.
    def ordered(additions)
      pending = additions.dup
      names = additions.to_set { |a| Bibkit.fold(a.key) }
      done = Set.new
      out = []
      until pending.empty?
        ready = pending.select { |a| (a.hit.item.macros.to_set & names).subset?(done) }
        ready = [pending.first] if ready.empty? # a cycle: keep going in order
        ready.each { |a| done << Bibkit.fold(a.key) }
        out.concat(ready)
        pending -= ready
      end
      out
    end

    def blocks_for(addition)
      alternatives = addition.alternatives.each_with_index.map { |hit, i| alternative(hit, addition.key, i + 2) }
      [addition.hit.item.text.b] + alternatives
    end

    def alternative(hit, key, number)
      marker = "% leeni-bib-fix: alternative #{number} for #{key} (from #{File.basename(hit.file.path.to_s)} " \
               "line #{hit.item.line}); keep one version under the key #{key} and delete the other"
      text = hit.item.text.b
      prefix = text[BLOCK_PREFIX].to_s.bytesize
      renamed = text.byteslice(0, prefix) + "#{key}#{ALT_TAG}#{number}".b + text.byteslice((prefix + key.bytesize)..)
      "#{marker.delete('@').b}\n#{renamed}"
    end

    def local_entry?(key) = @local.any? { |f| f.entries_for(key).any? }

    def local_macros
      @local_macros ||= @local.map(&:defined_macros).reduce(Set.new, :|)
    end

    def local_commands
      @local_commands ||= @local.map(&:defined_commands).reduce(Set.new, :|)
    end
  end
end
