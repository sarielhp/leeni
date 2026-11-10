# Bibkit: the `.bib` library, and `--bib-fix`

Bibkit is leeni's library for `.bib` files as data. It lives in
`lib/leeni/bibkit_*.rb` under the `Bibkit` namespace and is bundled into the
standalone `leeni` like every other module.

## Boundary

- Bibkit depends on the Ruby standard library only. It never requires a leeni
  module, prints, colours, or reads leeni's options: it takes paths and
  strings and returns data. leeni decides what to do with it.
- Its tests (`test/test_bibkit*.rb`) never run TeX.
- Running BibTeX or Biber, reading their logs, CLI options and alerts stay in
  leeni (`lib/leeni/bib_fix.rb`, `bib_checks.rb`, `bib_manager.rb`,
  `diagnostics.rb`).

## Checks on every build

`bib_checks.rb` scans every `.bib` file the paper uses (its own and those
found through `BIBINPUTS`) and raises an alert for each problem Bibkit
reports, at the file and line. The common one is a `%` "comment" after a
field value: `%` is not a comment character in `.bib` files, so BibTeX stops
reading the entry there ("I was expecting a `,' or a `}'", which leeni now
explains), while Biber accepts it silently. Results are cached in the build
directory by file size and modification time, so a large shared collection
is scanned once.

## Layers

| File | Contents |
|---|---|
| `bibkit_scanner.rb` | Tolerant scanner. Splits text into top-level blocks (`@type{...}` or `@type(...)`), keeping each block's original text, file and line. Between blocks a `%` comments out the rest of the line, as in Biber; an `@` on such a line is still a `Problem` (`% @` fails), because BibTeX has no comment character and starts an entry at any `@`. A block that does not parse becomes a `Bibkit::Problem` and scanning resumes at the next `@`. Never raises on content. |
| `bibkit_file.rb` | `Bibkit::BibFile`: the blocks of one file, indexed by key (case-insensitive lookup kept separate from exact lookup), `@string` name and the commands each `@preamble` defines. Per entry: fields as raw value text, `@string` macros used, `\commands` used, `crossref`/`xdata` parents. |
| `bibkit_collection.rb` | `Bibkit::Collection`: an ordered set of `BibFile`s. Built from a TeX search path (`BIBINPUTS` syntax: `:` separated, a trailing `//` searches subdirectories, empty elements are TeX's defaults and are skipped). Earlier files have priority. Lookup of entries, string definitions and preambles that define a command. |
| `bibkit_fixer.rb` | `Bibkit::Compare`: field names lower-cased, fields sorted, whitespace collapsed, ties (`~`) and braces ignored, bookkeeping fields ignored (`file`, `timestamp`, `owner`, `abstract`, `annote`, `annotation`, `keywords`, `date-added`, `date-modified`, `bdsk-*`); `covers?` when one version contains everything another says. `Bibkit::Fixer`: given the local files, a collection, missing keys and undefined macros, plans what to add: entries, their `crossref`/`xdata` parents, the `@string` definitions they need (and those those build on), the `@preamble` blocks defining commands they use, alternatives, keys found nowhere, case-only near misses. Pure: produces a `Plan` and the new file text, writes nothing. |

## `--bib-fix`

```
l --bib-fix [--dry-run] [paper.tex]
```

1. Build as usual.
2. Find the paper's bibliography files (from the `.bcf` for Biber, from
   `\bibdata` for BibTeX). Every one must lie inside the project (not reached
   through `../` or a symlink out of it); otherwise stop and suggest `-I`.
   The target is `<paper>.bib` if the paper uses it, else the first file the
   paper names.
3. Missing keys come from the same source as `--bib-missing`; undefined macros
   from the `.blg` (`Warning--string name "x" is undefined` for BibTeX,
   `undefined macro "x"` for Biber).
4. Search the collection: the `bib_fix_sources` config list first (files or
   directories, in order), then `BIBINPUTS`. Files inside the project are not
   searched.
5. Add to the target: `@string` and `@preamble` blocks at the top (BibTeX
   needs a macro defined before its first use), entries at the end, copied
   exactly as written. The previous file is kept as `<file>.bak`.
6. Rebuild and report what was added, what was not found anywhere, and keys
   that exist only with different capitalisation (copied: never).

`--dry-run` prints the plan and changes nothing.

### Conflicts

A key with several candidates that differ after normalisation, where no
version covers the others (a version with an extra `url` covers one without
it and replaces it): the highest-priority candidate is added as the live
entry. When it comes from a `bib_fix_sources` file the others are dropped;
otherwise each other variant is
added as a real entry under a marked key, after a marker comment:

```
% leeni-bib-fix: alternative 2 for Agarwal94 (from geom.bib line 12345); keep one version under the key Agarwal94 and delete the other
@inproceedings{Agarwal94_leeni_alt_2, ...}
```

A real entry is needed because BibTeX parses an entry even inside
`@comment{...}`; an uncited entry is ignored by both BibTeX and Biber (except
under `\nocite{*}`). The marker comment contains no `@`, which BibTeX would
take as the start of an entry.

Every build that runs raises an alert, at the file and line of the entry,
while a bibliography file of the paper still contains a `_leeni_alt_` entry
(an up-to-date cached build prints nothing, as for every alert).

## Configuration

```jsonc
// Files or directories --bib-fix searches before BIBINPUTS, highest
// priority first. A candidate from here wins any conflict outright.
"bib_fix_sources": []
```

## Testing

- Unit tests per layer, including the format's corners: parenthesised
  entries, `#` concatenation, quotes inside braces, braces inside quotes,
  `@comment`, junk between and inside entries, unbalanced blocks.
- A corpus check (full tier, `test_bibkit_corpus.rb`) over the `.bib` files
  TeX Live ships: every line that starts an entry yields an entry or a
  reported problem.
- Checked by hand on a personal collection (about 6 MB, 34,000 entries
  with the TeX Live files): two genuinely broken entries reported, junk such
  as `annote = {230} %DONE` recorded on 27 kept entries, a 4.7 MB file
  scanned in 0.7 s.
- `--bib-fix` end to end for BibTeX and Biber papers.

## Other users of Bibkit

- `-B` for BibTeX papers (`bib_extractor.rb`): the fixer's dependency closure
  over the paper's own `.bib` files, every source preferred so the first entry
  of a key wins as in BibTeX; `\nocite{*}` takes every entry. No `bibtool`.
- `bib_locator.rb` (file and line of an entry and of a field, for
  diagnostics): a case-insensitive lookup in the parsed file, cached by size
  and modification time; `BIBINPUTS` is expanded as TeX does (`//`).
- The `--bib-fix` hint: when a normal build has missing citations and the
  paper's bibliography is its own, `bib_checks.rb` looks the keys up in
  `bib_fix_sources` and `BIBINPUTS` (key lists cached per file) and the
  diagnostics name what `l --bib-fix` would add.

## Later

- Near-miss keys (typos), duplicate detection by DOI or title and year,
  linting of a whole collection.
