# write-rbs skill

Team conventions for writing RBS type signatures in dd-trace-rb, enforced on
every edit to `sig/**/*.rbs` and `vendor/rbs/**/*.rbs` by the `require-skill`
hook (see `../../hooks/README.md`).

## Layout

- `SKILL.md` – the agent-facing instructions. Kept lean: the rules that apply
  every time, plus pointers into `references/`. This is what loads into context
  when the skill triggers, so it stays short on purpose.
- `references/` – one file per technique (interfaces, type aliases, generics,
  procs, class definitions, Steep annotations, inline RBS). Loaded on demand when
  `SKILL.md` points to it. This is where the worked examples live.

## Editing conventions

- **RFC keywords.** Rules use `MUST` / `NEVER` / `SHOULD` (RFC 2119 sense) so the
  strength of each rule is unambiguous. Reserve `MUST`/`NEVER` for hard rules and
  `SHOULD` for judgment calls.
- **Good/bad contrast in SKILL.md is inline.** Show it on one line, for example
  `` write `Hash`, not `::Hash` ``. Never use a fenced block. Put full `# Good` /
  `# Bad` code blocks in `references/`, where the extra length pays for itself.
- **Reference example format:** a reference entry shows the rule, then a fenced
  RBS block with `# Good` and `# Bad` forms. It reads and edits like the
  signatures it describes.
