# frozen_string_literal: true

# Bibkit, the .bib library: scanner, collection, comparison and fixer. No TeX
# runs here; see test_bib_fix.rb for --bib-fix end to end.

require_relative 'test_env'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/leeni/bibkit_fixer'

class TestBibkitScanner < Minitest::Test
  def scan(text) = Bibkit::Scanner.scan(text, 'x.bib')

  def test_entries_strings_preambles_and_comments
    items, problems = scan(<<~BIB)
      Free text with an email: someone@example.org is ignored.
      @string{DCG = "Discrete Comput. Geom."}
      @preamble{ "\\providecommand{\\CNFX}[1]{#1}" }
      @comment{anything {nested} here}
      @Article{key1, author = {A. B{\\"o}hm}, journal = DCG # " (special)", year = 2001,}
      @book(key2, title = "Quoted {with "inner" quotes}", year = {1999})
    BIB
    assert_empty problems
    assert_equal %i[string preamble comment entry entry], items.map(&:kind)
    entry = items[3]
    assert_equal 'key1', entry.key
    assert_equal 5, entry.line
    assert_equal ['dcg'], entry.macros
    assert_equal 'DCG # " (special)"', entry.field('JOURNAL').value
    assert_equal '"Quoted {with "inner" quotes}"', items[4].field('title').value
  end

  def test_text_is_kept_byte_for_byte
    text = "@misc{k,\n  note   = {Latin-1 \xE9},\n  year = 1 }\n".b
    items, = scan(text)
    assert_equal text.strip, items.first.text
  end

  def test_junk_after_a_value_keeps_the_entry_and_records_it
    items, problems = scan("@article{k, annote = {230} DONE\n}\n@article{next, year=1}\n")
    assert_empty problems
    assert_equal %w[k next], items.map(&:key)
    assert_match(/unexpected text "DONE"/, items.first.problems.first.message)
  end

  def test_broken_entry_is_reported_and_scanning_resumes
    items, problems = scan(<<~BIB)
      @article{bad, author = "A and B},
        title = "T"}

      @article{good, year = 2000}
    BIB
    assert_equal ['good'], items.map(&:key)
    assert_equal 1, problems.size
    assert_equal 1, problems.first.line
  end

  def test_runaway_brace_does_not_swallow_the_next_entry
    items, problems = scan("@article{bad, title = {Open\n}\n@article{good, year = 2000}\n")
    assert_includes items.map(&:key), 'good'
    refute_empty problems
  end
end

class TestBibkitCollection < Minitest::Test
  def test_search_path_order_recursion_preferred_and_exclusion
    Dir.mktmpdir('bibkit') do |root|
      write(root, 'pref/p.bib', '@book{k, title={Preferred}}')
      write(root, 'flat/a.bib', '@book{k, title={Flat}}')
      write(root, 'flat/sub/deep.bib', '@book{deep, title={Deep}}')
      write(root, 'tree/sub/t.bib', '@book{k, title={Tree}}')
      write(root, 'project/local.bib', '@book{k, title={Local}}')
      path = ["#{root}/flat", '', "#{root}/tree//", "#{root}/project"].join(':')
      col = Bibkit::Collection.build(preferred: ["#{root}/pref/p.bib"], search_path: path, exclude: ["#{root}/project"])
      titles = col.entries_for('k').map { |h| h.item.field('title').value }
      assert_equal %w[{Preferred} {Flat} {Tree}], titles
      assert_equal [true, false, false], col.entries_for('k').map(&:preferred)
      assert_empty col.entries_for('deep'), 'a directory without // is not searched recursively'
    end
  end

  def test_case_insensitive_lookups
    file = Bibkit::BibFile.new("@string{Dcg = {D}}\n@book{MixedKey, year=1}\n@preamble{\"\\newcommand{\\Foo}{x}\"}")
    assert_empty file.entries_for('mixedkey')
    assert_equal ['MixedKey'], file.entries_like('mixedkey').map(&:key)
    refute_nil file.string_for('DCG')
    assert_equal 1, file.preambles_defining('Foo').size
  end

  def write(root, rel, text)
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end
end

class TestBibkitCompare < Minitest::Test
  def item(text) = Bibkit::Scanner.scan(text).first.first

  def test_typography_and_bookkeeping_fields_do_not_count
    a = item('@article{k, author = "P.~Lindstrom", title = {{Voronoi} Diagrams}, file = {a.pdf}}')
    b = item("@ARTICLE{k,\n  TITLE = \"Voronoi   Diagrams\",\n  author = {P. Lindstrom}, abstract = {x}}")
    assert Bibkit::Compare.same?(a, b)
  end

  def test_a_richer_version_covers_a_poorer_one
    poor = item('@article{k, author = {A}, year = 2000}')
    rich = item('@article{k, author = {A}, year = 2000, url = {http://x}}')
    assert Bibkit::Compare.covers?(rich, poor)
    refute Bibkit::Compare.covers?(poor, rich)
  end
end

class TestBibkitFixer < Minitest::Test
  STRINGS = <<~BIB
    @string{PROC = "Proc. " # VENUE}
    @string{VENUE = "SoCG"}
    @preamble{"\\providecommand{\\CNFX}[1]{(#1)}"}
  BIB
  ENTRIES = <<~BIB
    @inproceedings{child, author={C}, title={Child}, crossref={parent}, note={\\CNFX{x}}}
    @proceedings{parent, title={Parent}, booktitle=PROC, year=2001}
    @book{clash, author={A}, title={One}}
    @book{Upper, title={Case}}
  BIB
  OTHER = "@book{clash, author={A}, title={Two}}\n@book{clash, author={A}, title={One}, url={u}}\n"

  def fixer(local_text = "@book{have, journal=jan}\n", preferred: false)
    sources = [[Bibkit::BibFile.new(ENTRIES, 'entries.bib'), preferred], [Bibkit::BibFile.new(STRINGS, 'strings.bib'), false],
               [Bibkit::BibFile.new(OTHER, 'other.bib'), false]]
    @local_text = local_text
    Bibkit::Fixer.new([Bibkit::BibFile.new(local_text, 'paper.bib')], Bibkit::Collection.new(sources))
  end

  def test_plan_follows_parents_strings_and_preambles
    fx = fixer
    plan = fx.plan(missing_keys: %w[child have nowhere upper], undefined_macros: ['GONE'])
    assert_equal %w[child parent], plan.entries.map(&:key)
    assert_equal %w[PROC VENUE], plan.strings.map(&:key)
    assert_equal 1, plan.preambles.size
    assert_equal ['nowhere'], plan.not_found
    assert_equal({ 'upper' => ['Upper'] }, plan.case_hints)
    assert_equal ['gone'], plan.unknown_macros
  end

  def test_render_defines_strings_before_use_and_marks_alternatives
    fx = fixer
    plan = fx.plan(missing_keys: %w[child clash])
    out = fx.render(@local_text, plan)
    assert_operator out.index('@string{VENUE'), :<, out.index('@string{PROC'), 'a @string follows the strings it uses'
    assert_operator out.index('@preamble'), :<, out.index('@book{have')
    assert_operator out.index('@book{have'), :<, out.index('@inproceedings{child')
    # the version with the extra url covers the first; only "Two" conflicts
    assert_includes out, '@book{clash, author={A}, title={One}, url={u}}'
    assert_includes out, '% leeni-bib-fix: alternative 2 for clash (from other.bib line 1)'
    assert_includes out, '@book{clash_leeni_alt_2, author={A}, title={Two}}'
    assert_equal [['clash_leeni_alt_2', out.lines.index { |l| l.include?('clash_leeni_alt_2') } + 1]], Bibkit.alternatives_in(out)
    rescanned = Bibkit::BibFile.new(out)
    assert_empty rescanned.problems
    refute_includes out.lines.grep(/leeni-bib-fix/).join, '@'
  end

  def test_a_preferred_source_wins_outright
    fx = fixer(preferred: true)
    plan = fx.plan(missing_keys: %w[clash])
    assert_empty plan.conflicts
  end
end
