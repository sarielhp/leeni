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

- Released: 1.0.101 (tag `v1.0.101`, installed locally and on all hosts with
  `sync_all install`).
- **Unmerged branch `texse-tool`** (2 commits on top of 1.0.101, medium gate
  passing): `tools/texse_corpus`, the fixes from TeX.SE batches 4 and 5
  (minted/fancyvrb continuation lines, dropped-text cascades, the frame
  missing-`$` locator skipping display math, babel's removed language names,
  per-document engine in the tool). Next step: merge, then release when asked.

## Corpora (all in `datasets/`, ignored by git)

| Directory | What | Tool |
|---|---|---|
| `datasets/texse/` | TeX Stack Exchange questions (CC BY-SA) whose documents still fail; batches 1–5 run | `tools/texse_corpus` |
| `datasets/texfix/` | TeX-Fix-Bench: 6,568 documents with one injected fault and its fix line | `tools/fault_corpus` |
| `datasets/own_recent/`, `datasets/own_sample/` | Copies of the maintainer's own papers. Private: never commit names or text from them | `tools/mutate_corpus`, `tools/compare_corpus` |

`datasets/texse/README.md` and `datasets/texfix/corpus/README.md` record how
each was built and what each batch found.

TeX.SE has been the most productive source: each batch of 50 found two to four
real faults, most of them general (beamer frames, packages loaded by other
packages, dropped text). TeX-Fix-Bench was sampled twice (360 tasks); a full
run (~9 h) was judged not worth it.

## Resuming

```bash
# next TeX.SE batch: about 250 fetched beamer/biblatex/bibtex documents are not run yet
tools/texse_corpus prepare -n 50 datasets/texse
tools/texse_corpus run datasets/texse          # lists documents where leeni's first error differs from TeX's

# more questions (free API quota is about 300 requests a day)
tools/texse_corpus fetch -t tikz-pgf -q error -p 1-2 datasets/texse

# regression check over every TeX.SE document run so far
tools/texse_corpus run -b datasets/texse/corpus/selected.json -o /tmp/texse-all.json datasets/texse
```

For each flagged document, compare leeni's line with the source and TeX's line.
A real fault gets a fix, an error corpus case (`docs/errors/NN_*`, drafted with
`tools/test_error_corpus --draft`) or a unit test that fails without the fix,
and the index count in `docs/errors/README.md` and `docs/architecture.md`.

## Known open items

- `test_engine_killed_by_sigpipe_leaves_no_cut_off_aux_behind`
  (`test/test_pdf_driver_integration.rb`) fails now and then under load; four
  parallel copies reproduce it. The driver's late fatal message is missed; the
  read timing in `drain_reader` (`lib/leeni/build_runtime.rb`) should scale
  with load. Rerunning the gate passes.
- After babel stops on an unknown language, an error raised inside babel's own
  macros (`File ended while scanning use of \bbl@tempe`) is still listed, at
  line 0, with a brace hint.
- A glossaries entry defined in the document body can be reported, on a
  rebuild, inside the generated `.glsdefs`.
- `tools/texse_corpus run` builds each document twice (`--json`, then `-llm`);
  a document whose errors change between builds (longtable) is flagged
  `llm_disagree` although both renderers agree on the same build.

## Rules learned the hard way

- Release with `tools/release`; if it stops in the bump's full gate, finish
  with `tools/bump --resume`, never by rerunning `tools/release`.
- Commit only through `tools/commit`. Timing tests can fail under load:
  rerun them alone before suspecting a change.
- A failed BibTeX or Biber run is an error even when a shipped `.bbl` exists.
- Patching Ruby through shell heredocs has repeatedly lost backslashes in
  regexes; edit source files with an editor tool.
- The corpus tools stop a timed-out leeni with TERM before KILL so it stops its
  TeX run; a KILL leaves a looping pdflatex behind.
