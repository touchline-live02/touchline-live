# Contributing

This is a small native macOS project licensed under the [MIT License](LICENSE).
Preserve truthful attribution when contributing or redistributing material.

Keep changes focused. Preserve the read-only helper, exact-build gating, field
status semantics, capture/detach lifecycle, local queries and persisted formats.
A different FM build requires independent layout validation, not a relaxed gate.

Use the portable test commands in the README. `test-query.sh` creates a small
synthetic snapshot by default; it also accepts a locally owned snapshot path.
Strong golden tests cover the analytical engines and should not be replaced with
merely plausible outputs. Label/source attribution must stay truthful.

Never commit player captures, transport files, diagnostics, facepack files,
credentials, generated applications/helpers or compiler/Python caches. Do not
attach private career data to issues; use synthetic reproductions or carefully
reviewed minimal examples. Review all image/document metadata before adding assets.

For publication, build/test a separate copy and package the clean source through
`tools/public_source.py`. Its manifest and archive validation are stricter than
ignore rules. See [source packaging](docs/PUBLIC_SOURCE.md).
