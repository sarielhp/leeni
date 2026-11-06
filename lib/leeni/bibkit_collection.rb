# frozen_string_literal: true

# ==============================================================================
# lib/leeni/bibkit_collection.rb
#
# Bibkit::BibFile indexes the blocks of one .bib file; Bibkit::Collection is
# an ordered set of them, searched first to last. A collection is built from
# a TeX search path (BIBINPUTS syntax) and an optional list of preferred
# files or directories that come first.
# ==============================================================================

require_relative 'bibkit_scanner'

module Bibkit
  # \newcommand{\x}, \providecommand\x, \renewcommand*{\x}, \DeclareRobustCommand{\x}, \def\x
  DEFINES_COMMAND = /\\(?:(?:re)?newcommand|providecommand|DeclareRobustCommand)\*?\s*\{?\s*\\([A-Za-z]+)|\\def\s*\\([A-Za-z]+)/

  class BibFile
    attr_reader :path, :items, :problems

    def self.load(path)
      new(File.binread(path), path)
    end

    def initialize(text, path = nil)
      @path = path
      @items, @problems = Scanner.scan(text, path)
      @problems += @items.flat_map(&:problems)
      build_indexes
    end

    def inspect = "#<Bibkit::BibFile #{@path || '(text)'}: #{@items.size} items>"
    def entries = @items.select(&:entry?)
    def strings = @items.select { |i| i.kind == :string }
    def preambles = @items.select { |i| i.kind == :preamble }

    # Entries whose key is exactly `key`.
    def entries_for(key) = @exact[key.to_s.b] || []

    # Entries whose key matches `key` ignoring case.
    def entries_like(key) = @folded[Bibkit.fold(key)] || []

    def string_for(name) = @strings[Bibkit.fold(name)]
    def defined_macros = @strings.keys.to_set
    def preambles_defining(command) = @commands[command.to_s.b] || []
    def defined_commands = @commands.keys.to_set

    private

    def build_indexes
      @exact = Hash.new { |h, k| h[k] = [] }
      @folded = Hash.new { |h, k| h[k] = [] }
      @strings = {}
      @commands = Hash.new { |h, k| h[k] = [] }
      @items.each { |item| index(item) }
    end

    def index(item)
      case item.kind
      when :entry
        @exact[item.key.b] << item
        @folded[Bibkit.fold(item.key)] << item
      when :string
        @strings[Bibkit.fold(item.key)] ||= item
      when :preamble
        Bibkit.commands_defined_by(item).each { |cmd| @commands[cmd] << item }
      end
    end
  end

  def self.commands_defined_by(item)
    item.text.scan(DEFINES_COMMAND).map { |a, b| (a || b).b }.uniq
  end

  # A hit in a collection: the item, the file it came from and whether that
  # file is one of the preferred sources.
  Hit = Struct.new(:item, :file, :preferred)

  class Collection
    attr_reader :files

    # preferred: files or directories searched first, in order. search_path:
    # a BIBINPUTS-style string. Files under any `exclude` directory (the
    # project itself) are left out.
    def self.build(preferred: [], search_path: nil, exclude: [])
      excluded = exclude.map { |dir| real(dir) }.compact
      ranked = expand(Array(preferred)).map { |f| [f, true] } +
               expand(search_path.to_s.split(File::PATH_SEPARATOR)).map { |f| [f, false] }
      seen = Set.new
      picked = ranked.select do |path, _|
        real_path = real(path)
        real_path && excluded.none? { |dir| real_path.start_with?("#{dir}/") } && seen.add?(real_path)
      end
      new(picked.map { |path, pref| [BibFile.load(path), pref] })
    end

    # Each element is a .bib file or a directory; a directory ending in //
    # is searched recursively. Empty elements (TeX's defaults) are skipped.
    def self.expand(elements)
      elements.flat_map do |element|
        element = element.to_s.strip.delete_prefix('!!')
        next [] if element.empty?

        recursive = element.end_with?('//')
        path = File.expand_path(element.chomp('/').chomp('/'))
        next [path] if File.file?(path)
        next [] unless File.directory?(path)

        Dir.glob(File.join(path, recursive ? '**/*.bib' : '*.bib'))
      end
    end

    def self.real(path)
      File.realpath(path)
    rescue SystemCallError
      nil
    end

    # sources: [[BibFile, preferred?], ...] in priority order.
    def initialize(sources)
      @sources = sources
      @files = sources.map(&:first)
    end

    def entries_for(key) = hits { |f| f.entries_for(key) }
    def entries_like(key) = hits { |f| f.entries_like(key) }
    def strings_for(name) = hits { |f| [f.string_for(name)].compact }
    def preambles_defining(command) = hits { |f| f.preambles_defining(command) }
    def problems = @files.flat_map(&:problems)

    private

    def hits
      @sources.flat_map { |file, pref| yield(file).map { |item| Hit.new(item, file, pref) } }
    end
  end
end
