# Handoff: Diagnostic Oracles and Real-World Corpora

Last updated 2026-11-19. Read this before resuming work on leeni's diagnostics
or its test corpora.

## Goal

Check that leeni's diagnostics are *correct*, not only that it runs: every
error TeX finds is reported, at the line the fault is on (at least as close as
TeX's own line), with the right category and hint, and `-llm` and `--json`
agree. The checks run leeni on documents whose faults are known or can be
judged against TeX.

## State

- Released: 1.0.102, which includes all the TeX.SE work through batch 10
  (branch `texse-tool` merged into master). Installed locally.
- The run was stopped by request after batch 11. Batch 11's flags are **not
  reviewed yet** (see below).
- The fetched TeX.SE questions are used up: every downloaded document that
  still fails has been in a batch. The next batch needs a new `fetch`.

## Corpora (all in `datasets/`, ignored by git)

| Directory | What | Tool |
|---|---|---|
| `datasets/texse/` | TeX Stack Exchange questions (CC BY-SA) whose documents still fail; 1,088 extracted, 440 failing ones run in batches 1–11 | `tools/texse_corpus` |
| `datasets/texfix/` | TeX-Fix-Bench: 6,568 documents with one injected fault and its fix line | `tools/fault_corpus` |
| `datasets/own_recent/`, `datasets/own_sample/` | Copies of the maintainer's own papers. Private: never commit names or text from them | `tools/mutate_corpus`, `tools/compare_corpus` |

`datasets/texse/README.md` and `datasets/texfix/corpus/README.md` record how
each was built and what each batch found. Questions fetched so far: tag
`errors` (pages 1–7), and `beamer`, `biblatex`, `bibtex`, `tikz-pgf`,
`tables`, `hyperref` with "error" in the title (pages 1–2 each).

## Results per batch (50 documents unless noted)

| Batch | Source | Real leeni bugs fixed |
|---|---|---|
| 1–3 | `errors` tag | many (beamer frames, packages loaded by packages, dropped text, ...) |
| 4 | leftover `errors` documents | 3 |
| 5 | beamer, biblatex, bibtex | 2 |
| 6 | beamer | 5 (+1 in the harness) |
| 7 | 9 leftovers + a full regression run | 5 |
| 8 | tikz-pgf, tables, hyperref | 2 |
| 9 | same | 1 |
| 10 | same | 2 |
| 11 | 28 leftovers | not reviewed |

The rate is not clearly falling; what changes is the kind of bug. Early
batches found faults hitting many documents (locations inside packages and
beamer frames, log parsing). Later ones find narrower ones: one package's
error message without a hint, a package-specific cascade, an edge of a
location heuristic. Most flagged differences are now leeni being right where
TeX's line is not useful (at `\end{frame}`, inside a `.sty`). New tags bring
new packages and so new bugs; a clean batch is likelier once tags repeat
packages already covered.

## Batch 11: flags to review

- 644444: undefined control sequence at line 11 (a `\newcolumntype` using
  `\currentprecision`) where TeX reports line 17 (the table row); probably
  right, check what is undefined. Its second error is siunitx's
  `Illegal parameter number in definition of \l__siunitx_table_collect_tl`.
- 654633: `[T5]{fontenc}` without the Vietnamese fonts: file_not_found at the
  `\usepackage` line, plus "Encoding scheme T5 unknown" on the same line, which
  could be folded into it.
- 749679: memoize's "No suitable Perl module for PDF processing": `generic`, no
  hint (install PDF::API2 or use memoize's python extraction); second error at
  line 570.
- 751123: undefined `\TTTa` at line 9 vs TeX's 14 (the use of a macro defined
  at 9); probably right.

## Resuming

```bash
# new questions (free API quota is about 300 requests a day)
tools/texse_corpus fetch -t <tag> -q error -p 1-2 datasets/texse
tools/texse_corpus prepare -n 50 datasets/texse
tools/texse_corpus run datasets/texse          # lists documents where leeni's first error differs from TeX's

# regression check over every TeX.SE document run so far (about 40 min), then
# compare with the previous run's JSON by id: first location, flags, error count
tools/texse_corpus run -b datasets/texse/corpus/selected.json -o <scratch>/texse-all.json datasets/texse
```

Unused tags worth trying: `graphics`, `floats`, `math-mode`, `fonts`,
`xetex`, `luatex`, `babel`, `listings`, `siunitx`, `pgfplots`, `amsmath`.

For each flagged document, compare leeni's line with the source and TeX's line.
A real fault gets a fix, an error corpus case (`docs/errors/NN_*`, drafted with
`tools/test_error_corpus --draft`; the last is 80) or a test in
`test/test_texse_regressions.rb` that fails without the fix, and the index
count in `docs/errors/README.md` and `docs/architecture.md`. After a fix that
touches log parsing or a locator, rerun the full regression and look at every
document whose result changed.

## Known open items

- Load-sensitive tests fail now and then in the gate and pass alone:
  `test_relatex_synctex.rb` (`test_next_build_stops_previous_run`) and
  `test_engine_killed_by_sigpipe_leaves_no_cut_off_aux_behind`
  (`test_pdf_driver_integration.rb`; the read timing in `drain_reader`,
  `lib/leeni/build_runtime.rb`, should scale with load). Rerun the gate.
- Harness limits (`tools/texse_corpus`, `tools/mutate_corpus`):
  - it builds each document twice (`--json`, then `-llm`), so a document whose
    errors change between builds (longtable, TikZ externalization) is flagged
    `llm_disagree` although both renderers agree on one build;
  - TeX's first error is read from the first pass, so a document leeni builds
    cleanly after a retried pass (TeX.SE 360474) is flagged `silent`;
  - `[\directlua]:1:` is not read as a TeX error location (367913 is flagged
    `leeni_only`).
- An undefined macro used on several lines is reported at the use nearest
  TeX's line, not its first use (289687: `\mywidth` at 8, first used at 7).
- After babel stops on an unknown language, an error raised inside babel's own
  macros can still be listed, at line 0.
- A glossaries entry defined in the document body can be reported, on a
  rebuild, inside the generated `.glsdefs`.

## Rules learned the hard way

- Release with `tools/release`; if it stops in the bump's full gate, finish
  with `tools/bump --resume`, never by rerunning `tools/release`.
- Commit only through `tools/commit`. Timing tests can fail under load:
  rerun them alone before suspecting a change.
- A failed BibTeX or Biber run is an error even when a shipped `.bbl` exists.
- Edit Ruby source with an editor tool, or with a script that reads its new
  text from a file. Shell heredocs and quoted `-e` scripts have repeatedly lost
  backslashes in regexes, and `String#sub!` with a replacement *string*
  interprets `\\`, `\1` and `\'` (post-match): use the block form.
- `git stash` to compare with the committed code also stashes a modified test
  file; to check that a test fails without a fix, disable the fix instead.
- The corpus tools stop a timed-out leeni with TERM before KILL so it stops its
  TeX run; a KILL leaves a looping pdflatex behind.
- Run long corpus jobs under `nice -n 19`.
- A TeX.SE result depends on the machine's TeX Live, not only on leeni: a
  different package revision moves TeX's line inside a `.sty` or fixes the
  question's bug outright. Keep TeX Live updated (`tlmgr update --self --all`)
  on every machine that runs the corpus, and compare a new machine's full run
  with `datasets/texse/regression-baseline.json` before trusting its flags.
- leeni builds with `-no-mktex=tfm`, so a font metric Metafont would generate
  (the Cyrillic `lh` fonts of a `T2A` document) is missing on a new machine
  until it is made once outside leeni, for example `mktextfm lass1095`
  (TeX.SE 676135 needs 18 of them; the list is in `~/.texlive/texmf-var/fonts/tfm`
  on a machine that has them).
