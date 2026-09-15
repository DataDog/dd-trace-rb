Override for `reviewers/conventions.md` (in the core skill folder) — read that file first, then this.

# Codebase conventions — dd-trace-rb specifics

These addenda apply to `lib/**/*.rb` only. Do not flag `ENV` or `Time.now` in
specs, `tasks/`, gemfiles, CI, or other non-library paths.

This file starts with one confirmed pattern and should grow — add the next
one you learn from review. Do not treat it as exhaustive.

The source of truth is [`AGENTS.md`](../../../AGENTS.md). Open that file for the topic under review; do not restate it here.

`DATADOG_ENV` vs `ENV` is already enforced by `CustomCops/EnvUsageCop` on
`lib/**/*` (see `.rubocop.yml`). Do not re-flag a direct `ENV` read that
RuboCop already covers. If RuboCop did not run, report `NOT VERIFIED` for
that check rather than inventing an ENV finding.

## `Datadog::Core::Utils::Time.now`, never `Time.now`

The time provider is configurable (`Core::Utils::Time.now_provider=`).
`Time.now` in `lib/**/*.rb` is a conventions finding — tests cannot override
it. **P1**. Do not flag `Time.now` outside `lib/`.

## Mechanical checks — run these, don't eyeball them

Check-mode only. Anything that would rewrite files is the author's to run.

```bash
bundle exec rake rubocop typecheck
```

If Bundler, RuboCop, or Steep is missing, report `NOT VERIFIED (<reason>)` rather than eyeballing format.
