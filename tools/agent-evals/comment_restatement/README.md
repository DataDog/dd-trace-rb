# Comment restatement agent evals

These evals check that code an agent produces in this repository obeys the
repository's comment rules, starting with the comment-restatement rule defined
by `.agents/skills/write-comment/SKILL.md`. Where the
`open_feature_guidance` suite verifies that an agent session discovers the
governing instruction files, this suite verifies the content the session
produces against the rules those files define.

Each case is a real coding task. For every case the runner performs two
one-shot agent calls:

- A **generation call** in a fresh, clean `master` checkout of the
  repository, given the case `task` prefixed with the prompt baseline
  (no cloning, work in the cwd repository only, no reads outside cwd,
  bundler on default settings).
- A **judge call**, read-only, given the produced diff, the governing rule
  text read at runtime from the checkout (single source of truth), and the
  verdict schema. The judge is instructed to apply the senior-engineer
  restatement test to every comment in the diff explicitly; a generic
  "find violations" prompt produces false greens.

A case passes when the judge returns an empty `verdicts` array.

## Running

Run all cases from any directory in the checkout:

```bash
ruby tools/agent-evals/comment_restatement/run.rb
```

Run one case, judge an existing diff, or point the suite at another
checkout:

```bash
ruby tools/agent-evals/comment_restatement/run.rb --case captured_string_byte_cap
ruby tools/agent-evals/comment_restatement/run.rb --case captured_string_byte_cap --diff /path/to/produced.diff
ruby tools/agent-evals/comment_restatement/run.rb --root /path/to/checkout
```

## Agent commands

The runner does not assume a specific coding agent. Both calls run a command
of your choosing: the prompt is written to the command's stdin and the agent's
final message is expected on stdout. The defaults follow this repository's
existing eval harness and use `codex exec`, the generation call sandboxed to
the per-case checkout through the `{ROOT}` placeholder in `--agent-command`.
Any other one-shot agent can be substituted the same way; model selection and
the execution environment belong to the command you pass, keeping this suite
independent of how agents are deployed.

Every flag has a short form (`-c`, `-x`, `-k`, `-r`, `-d`, `-a`); `--help`
lists them.

## Artifacts

Each case directory records the prompt, the agent stdout and stderr, the
produced diff, the judge prompt and output, and a `report.json` with the
verdicts. The per-case checkout is retained alongside them. The suite writes
nothing into the invoking checkout.

The suite is intentionally not wired into CI or LLMObs yet. Lint rules that
become mechanically enforceable after
[#6032](https://github.com/DataDog/dd-trace-rb/pull/6032) stay in the
executable lint configuration; this suite covers only the semantic rules no
cop can express.
