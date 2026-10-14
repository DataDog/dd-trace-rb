# Changelog message styles

House rules live in `Changelog/`. The write-good, proselint, and Harper
packages are not checked into this repo; CI downloads them from their
release zips (errata-ai/write-good, errata-ai/proselint, and the
Automattic-Harper port at vale-cli/Harper, whose POS-tagger dictionaries
land at `config/`), pinned by version and SHA256 (see
`.github/scripts/install_vale_styles.sh` and the pins in
`.github/workflows/check.yml`), so CI never runs unpinned content.
`.vale.ini` documents the per-rule calibration against the last 10
releases of CHANGELOG.md.

These rules are a CI gate, not a local tool: the vale binary and style
packages are installed by CI only, and `unreleased:vale` is its
invocation. Authors learn the rules from
`unreleased/README.md` and the write-changelog skill; CI annotations
are the revision signal.
