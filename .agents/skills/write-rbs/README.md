# write-rbs skill

Team conventions for writing RBS type signatures in dd-trace-rb, enforced on
every edit to `sig/**/*.rbs` and `vendor/rbs/**/*.rbs` by the `require-skill`
hook (see `../../hooks/README.md`)

## Layout

- `SKILL.md` – the agent-facing instructions. Kept lean: the rules that apply
  every time, plus pointers into `references/`. This is what loads into context
  when the skill triggers, so it stays short on purpose
- `references/` – one file per technique (interfaces, type aliases, generics,
  procs, class definitions, Steep annotations, inline RBS). Loaded on demand when
  `SKILL.md` points to it. This is where the worked examples live

## Editing conventions

- **RFC keywords.** Rules use `MUST` / `NEVER` / `SHOULD` (RFC 2119 sense) so the
  strength of each rule is unambiguous. Reserve `MUST`/`NEVER` for hard rules and
  `SHOULD` for judgment calls
- **Good/bad in SKILL.md is inline.** Contrast on one line – `` write `Hash`, not
  `::Hash` `` – never a fenced block. Full `# Good` / `# Bad` code blocks belong
  in `references/`, where the extra length pays for itself
- **Every reference example is a code block.** A reference entry shows the rule,
  then a fenced RBS block with `# Good` and `# Bad` forms, so it reads and edits
  like the signatures it describes
