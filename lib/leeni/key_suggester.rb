# frozen_string_literal: true

# ==============================================================================
# lib/leeni/key_suggester.rb
#
# "Did you mean" for undefined \ref and \cite keys.
# ==============================================================================

# Finds the defined key an undefined one was most likely meant to be. A key
# such as lem:main_result has a category prefix and a name. Confusing the
# category (\ref{lem:x} for a theorem labelled thm:x) is a different, and far
# more common, mistake than misspelling the name, so a prefix mismatch costs a
# fraction of an edit, as do a different separator (lem:x, lem-x, lem_x) and
# a difference in case. The name is compared by edit distance, where swapping
# two adjacent characters is one edit.
module LeeniKeySuggester
  PREFIXED_KEY = %r{\A([a-zA-Z]{1,8})[:_\-./](.+)\z}
  SEPARATORS = %r{[:_\-./]}
  PREFIX_COST = 0.3
  MISSING_PREFIX_COST = 0.5
  SEPARATOR_COST = 0.1
  CASE_COST = 0.1
  # Slack over the edits a name may take, for prefix, separator and case.
  COSMETIC_SLACK = 0.6
  MAX_SUGGESTIONS = 3

  module_function

  # The best candidates for key (ties all count, up to MAX_SUGGESTIONS), or [].
  def suggest(key, candidates)
    scored = candidates.uniq.filter_map do |candidate|
      next if candidate == key

      cost = cost(key, candidate)
      [cost, candidate] if cost
    end
    best = scored.map(&:first).min
    return [] unless best

    scored.select { |cost, _| cost <= best + 1e-9 }.map(&:last).sort.first(MAX_SUGGESTIONS)
  end

  # The cost of reading key as candidate, or nil when they are too far apart.
  # A separator need not end a prefix (main_result), so each key is also read
  # whole, and the cheaper reading counts. The edit budget follows the name
  # without its prefix, so reading a key whole does not widen it.
  def cost(key, candidate)
    own = readings(key)
    allowed = allowed_edits(normalize(own.last.last))
    own.product(readings(candidate)).filter_map { |a, b| reading_cost(*a, *b, allowed) }.min
  end

  def readings(key)
    match = key.match(PREFIXED_KEY)
    match ? [[nil, key], [match[1].downcase, match[2]]] : [[nil, key]]
  end

  def reading_cost(prefix_a, name_a, prefix_b, name_b, allowed)
    norm_a = normalize(name_a)
    norm_b = normalize(name_b)
    return nil if (norm_a.length - norm_b.length).abs > allowed

    edits = edit_distance(norm_a.downcase, norm_b.downcase, allowed)
    return nil if edits > allowed

    total = edits + prefix_cost(prefix_a, prefix_b) + cosmetic_cost(name_a, name_b)
    total <= allowed + COSMETIC_SLACK ? total : nil
  end

  def normalize(name) = name.gsub(SEPARATORS, '_')

  # Short names leave no room for a typo: lem:a is not lem:b.
  def allowed_edits(name)
    if name.length <= 3 then 0
    elsif name.length <= 7 then 1
    else 2
    end
  end

  def prefix_cost(prefix_a, prefix_b)
    return 0 if prefix_a == prefix_b
    return MISSING_PREFIX_COST if prefix_a.nil? || prefix_b.nil?

    PREFIX_COST
  end

  def cosmetic_cost(name_a, name_b)
    cost = 0
    cost += SEPARATOR_COST if name_a.scan(SEPARATORS) != name_b.scan(SEPARATORS)
    cost += CASE_COST if normalize(name_a) != normalize(name_b) && normalize(name_a).casecmp?(normalize(name_b))
    cost
  end

  # Optimal string alignment distance, giving up once every entry of a row
  # exceeds limit.
  def edit_distance(source, target, limit)
    prev2 = nil
    prev = (0..target.length).to_a
    source.each_char.with_index(1) do |ca, i|
      row = [i]
      target.each_char.with_index(1) do |cb, j|
        row << osa_step(prev, row, prev2, [source, target, i, j], ca == cb ? 0 : 1)
      end
      return limit + 1 if row.min > limit

      prev2 = prev
      prev = row
    end
    prev.last
  end

  def osa_step(prev, row, prev2, (source, target, i, j), sub)
    best = [prev[j] + 1, row[j - 1] + 1, prev[j - 1] + sub].min
    transposed = prev2 && i > 1 && j > 1 && source[i - 1] == target[j - 2] && source[i - 2] == target[j - 1]
    transposed ? [best, prev2[j - 2] + 1].min : best
  end
end
