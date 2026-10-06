# ArXiv test fixups

This directory records source repairs discovered while testing downloaded
ArXiv papers. A fixup is evidence about the input corpus; `leeni` and
`tools/test_arxiv` never apply one automatically. The original source remains
the test result, and a matching catalog entry is shown in its report.

ArXiv entries are named `<id>.json` below `fixups/arxiv/`. An entry matches only
when both its `arxiv_id` and `source_sha256` match the downloaded metadata. The
checksum prevents a repair from silently being reused for a revised source.

Each entry records the affected files and a proposed repair in descriptive
form. Future tooling may use these records to run a repaired build in a
separate workspace, but that is deliberately not part of the current test.

The JSON shape is documented in `schema.json`.
