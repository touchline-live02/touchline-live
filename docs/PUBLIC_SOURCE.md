# Source packaging

`tools/source_files.txt` is the approved publication set. The exporter rejects
missing/unexpected files, symlinks and unapproved directories, including bytecode,
logs, applications and local data. A working Git directory is ignored by source
validation but is never exported. Final exports may not contain one.

Build and run tests in a **separate copy**, leaving the publication source clean.
Do not zip a directory that has been used for tests or builds. Generate an absent/
empty export and an absent ZIP directly from the approved source bytes:

```sh
python3 -B tools/public_source.py --output ../touchline-source
python3 -B tools/public_source.py --archive ../touchline-source.zip
python3 -B tools/public_source.py --verify-export ../touchline-source
python3 -B tools/public_source.py --verify-archive ../touchline-source.zip
```

Run these commands from the clean source tree, not inside the final export. Do
not import Python modules or build inside that export afterward. Unexpected
files make validation fail even if Git would ignore them. A contaminated input
cannot be packaged by this workflow.

The ZIP contains only approved files and a SHA-256 manifest of relative filenames.
Every member is checked against the source bytes. ZIP timestamps, permissions
and metadata are normalized; no owner IDs, private paths, comments or extra fields
are stored. Ignore rules do not erase already published Git history.

`LICENSE` contains the project's MIT License and is a required entry in
`tools/source_files.txt`. A candidate missing it fails validation. The license is
included in the hash manifest and ZIP like every approved source file. Additional
files require explicit approval in `tools/source_files.txt`, followed by validation
and a fresh manifest/export/archive.
