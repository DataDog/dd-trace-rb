Override for `reviewers/conventions.md` (in the core skill folder) — read that file first, then this.

# Codebase conventions — dd-trace-rb specifics

This file starts with two confirmed patterns and should grow — add the next
one you learn from review. Do not treat it as exhaustive.

The source of truth is [`AGENTS.md`](../../../AGENTS.md). Open that file for the topic under review; do not restate it here. Only the two mechanically-missed rules below are spelled out.

## `DATADOG_ENV`, never `ENV`

Use `DATADOG_ENV` (see `docs/AccessEnvironmentVariables.md`). A new `ENV['DD_*']` / `ENV.fetch(...)` read in shipped code is a conventions finding — the wrapper is what lets tests and config inversion see the value. Treat a new production `ENV` read as **P1** (it will surprise the next person who mocks env); treat it as **P0** only when it also bypasses a required registration step (`rake local_config_map:generate`).

## `Datadog::Core::Utils::Time.now`, never `Time.now`

The time provider is configurable (`Core::Utils::Time.now_provider=`). `Time.now` in shipped code or in a spec that should be frozen is a conventions finding — tests cannot override it. **P1**.

## Mechanical checks — run these, don't eyeball them

Check-mode only. Anything that would rewrite files is the author's to run.

```bash
bundle exec rake rubocop typecheck
```

If Bundler, RuboCop, or Steep is missing, report `NOT VERIFIED (<reason>)` rather than eyeballing format.
