# Handoff: Diagnostic Oracles and Real-World Corpora

Last updated 2026-11-20. Read this before resuming work on leeni's diagnostics
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
- STOPPED on 2026-11-20 after batch 21 by the stopping rule below: batches 20
  and 21 gave no recurring mechanism. Batches 11-19 are fixed (after 1.0.102,
  local commits, not released; error corpus cases 81-89). Unbatched failing
  documents remain (fetched for batch 21); resume only to recheck after a
  TeX Live update or for a new class of fault.
- Stopping rule agreed on 2026-11-20 (long tail reached: a fix round now
  changes under 1% of the corpus, but each fix adds code, and three caused
  regressions that only the full run caught): from batch 18, fix only
  mechanisms seen in 2+ documents or with a general cause (engine, catcode,
  expl3, a silent stop); list one-package oddities under Known open items.
  Stop after two batches with no such fix; then use tools/mutate_corpus on
  own papers and rerun the TeX.SE regression after TeX Live updates. The full regression over all 490 documents run so far is the new
  `datasets/texse/regression-baseline.json`.
- 2026-11-20: questions fetched for `siunitx`, `pgfplots`, `math-mode`,
  `graphics`, `floats`, `fonts`, `xetex`, `luatex`, `babel`, `listings`,
  `amsmath` ("error" in the title, pages 1–2), so many failing documents are
  still unrun: continue with `prepare` and `run`, no fetch needed yet.

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
| 11 | 28 leftovers | 2 (fontenc encoding cascade, memoize hint) |
| 12 | siunitx, pgfplots, math-mode | 3 (siunitx with units, number inside a longer number, dropped text beside a brace error) |
| 13 | graphics, floats, fonts, xetex, luatex, babel, listings, amsmath | 8 (triaged by 15 parallel DeepSeek agents; see below) |
| 14 | leftovers of the same tags (100 docs) | 8 (LuaTeX-only packages, unbalanced write, runaway brace line, \\text in \\textsc, duplicates, bracket in an option value) |
| 15 | biber, fontspec, tikz-styles, cross-referencing, macros, expl3, chemistry, algorithms (100 docs) | 1 (dropped-text hint), plus a missing-font entry found in the regression |
| 16 | next 100 of those tags | 7 (Lua tracebacks and chunk lines, luacode engine refusal, space glyph, unicode-math clash hint, @ in a name without \makeatletter) |
| 17 | next 100 | 5 (engine refusal wordings, engine primitives in the body, expl3 names kept whole, an unknown option passed on to later packages, clash hint) |
| 18 | last 38 fetched | 1 recurring (blank line inside an argument closed after it) |
| 19 | minted, glossaries, tcolorbox, titlesec, ... (100) | 3 recurring (wrapped minted without \VerbatimEnvironment, end-of-file runaway at line 1, grouping across TeX lines) |
| 20 | rest of those (64) | none recurring: stop count 1 |
| 21 | tikz-pgf, beamer, tables pages 3-4 (100) | none recurring: stop count 2, corpus work stopped |

The rate is not clearly falling; what changes is the kind of bug. Early
batches found faults hitting many documents (locations inside packages and
beamer frames, log parsing). Later ones find narrower ones: one package's
error message without a hint, a package-specific cascade, an edge of a
location heuristic. Most flagged differences are now leeni being right where
TeX's line is not useful (at `\end{frame}`, inside a `.sty`). New tags bring
new packages and so new bugs; a clean batch is likelier once tags repeat
packages already covered.

## Working method (2026-11-20)

- The machine has 20 cores: run corpus jobs with `-j 14` (full regression
  about 12 minutes); more risks timeouts that show up as false flags.
- Mechanical work goes to opencode with the Lumen DeepSeek model:
  `opencode run -m litellm/lumen/deepseek-v4.1-flash-1017 "<task>"`, given a
  precise task file (what changed, exact files, tests to run, no lib/ or tools/
  edits, no commits). It wrote error corpus cases 81–83, the index counts and
  the regression tests well.
- Triage (since batch 13; `tools/texse_corpus triage -j 8 [-b run-batch-N.json]`
  since batch 14, reports in datasets/texse/triage/batch-N/): one opencode
  agent per flagged document, each given the flag line and a fixed prompt: copy the
  paper to scratch, run TeX and leeni, read both lines, write a report with a
  verdict (LEENI_RIGHT / LEENI_WRONG / HARNESS / UNSURE) and, if wrong, a
  minimal reproducer. On batch 13 every LEENI_WRONG verdict held, but one root
  cause was wrong (148271 blamed the brace checker; the trigger was an ignored
  Emergency stop): check each before fixing. In batches 14-15 the agents also
  miscounted columns twice and called right results wrong or unsure twice.
  Verdicts and lib/ changes stay with the main agent.
- The full regression after a fix round catches regressions from the fixes
  themselves (batch 14: a word-boundary fix broke \z@ without \makeatletter;
  a cascade fold dropped errors that came before the cascade). Diff every
  changed document against the committed leeni in a git worktree.

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

Tags not fetched yet: `tikz-styles`, `biber`, `fontspec`, `cross-referencing`,
`hyperref` pages 3+, `macros`, `expl3`, `chemistry`, `algorithms`.

For each flagged document, compare leeni's line with the source and TeX's line.
A real fault gets a fix, an error corpus case (`docs/errors/NN_*`, drafted with
`tools/test_error_corpus --draft`; the last is 83) or a test in
`test/test_texse_regressions.rb` that fails without the fix, and the index
count in `docs/errors/README.md` and `docs/architecture.md`. After a fix that
touches log parsing or a locator, rerun the full regression and look at every
document whose result changed.

## Known open items

- Seen once in batches 20-21, not fixed: an undefined command in a beamer
  frame reported again with token \end at \end{frame} (377031); an unclosed
  brace inside \newglossarystyle blamed on the outer brace (668443); minted's
  deferred 'Cannot locate file' taking TeX's l.N, not its own './main:16:'
  (686219); pgf arrow declarations typesetting values as dropped text
  (352096); fancyvrb's stray space after \VerbatimEnvironment (526284).
- A chained command that pipes the gate through tail hides its failure (batch
  19 was committed past a failing medium gate): check the gate's exit status.
- One-package oddities seen and not fixed: endfloat's figure/figure* mismatch
  (535982: line 0 shown as 1, brace hint); \resizebox{w}{}{...} running to
  the end of the file (665349); a class option with spaces around = leaking
  into geometry (696796); a source comment that looks like a log error
  (557099); alerts for another .tex file of the same directory (514235);
  siunitx's \ERROR sentinel named as the undefined command (574491); quotes
  loaded before babel spanish (297933).
- The system rexml gem (3.2.5, updated 2026-11-19) warns under `-w`;
  `tools/sample_arxiv` silences warnings around its `require`, since the test
  runner fails on warnings. Remove that once the gem is fixed.
- A pgfplots boxplot of all-zero data on a log axis gives "Missing number" at
  the plot's `};` with the generic hint (TeX.SE 227793); a hint naming log of
  zero would help.
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
- Never edit lib/ while a corpus run is going: every document builds with the
  current working tree, and a half-made edit turns hundreds of results into
  crashes (2026-11-20; the run had to be repeated).
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
