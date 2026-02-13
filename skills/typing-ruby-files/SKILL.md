---
name: typing-ruby-files
description: Precision-first typing workflow for one or a small list of dd-trace-rb lib/**/*.rb files with matching sig/**/*.rbs. Use when asked to fully type target files, reduce untyped aggressively, run Steep at normal and information severity, enforce transient-gap comment rules with upstream issue links, and produce compromise reports with file:line diagnostic evidence.
---

# Typing Ruby Files

## Overview

Type a small Ruby scope end-to-end: mapping, untyped baseline, edits, steep checks, and compromise reporting.
Prefer deterministic script outputs over ad-hoc manual reporting.

## Workflow

1. Resolve scope and stale paths first.
2. Capture pre-edit `untyped` inventory.
3. Apply Ruby and RBS edits for precision typing.
4. Enforce transient-gap comment policy when applicable.
5. Capture post-edit `untyped` inventory and delta.
6. Run mandatory steep checks at two severities.
7. Run targeted behavior specs when any `lib/**` runtime code changed.
8. Generate standardized markdown/json report with evidence.
9. Re-run eval scenarios after non-trivial changes to the skill.

## Commands

Set an artifact directory:

```bash
ARTIFACT_DIR=tmp/typing-skill-run
mkdir -p "$ARTIFACT_DIR"
```

Resolve targets (`lib/**/*.rb` only):

```bash
ruby skills/typing-ruby-files/scripts/resolve_scope.rb \
  --target lib/datadog/core/metrics/client.rb \
  --out "$ARTIFACT_DIR/scope.json"
```

Capture pre-edit `untyped`:

```bash
ruby skills/typing-ruby-files/scripts/audit_untyped.rb \
  --scope "$ARTIFACT_DIR/scope.json" \
  --phase before \
  --out "$ARTIFACT_DIR/untyped.before.json"
```

Run mandatory steep checks:

```bash
ruby skills/typing-ruby-files/scripts/run_steep_checks.rb \
  --scope "$ARTIFACT_DIR/scope.json" \
  --out "$ARTIFACT_DIR/steep.json"
```

Capture post-edit `untyped` and report:

```bash
ruby skills/typing-ruby-files/scripts/audit_untyped.rb \
  --scope "$ARTIFACT_DIR/scope.json" \
  --phase after \
  --baseline "$ARTIFACT_DIR/untyped.before.json" \
  --out "$ARTIFACT_DIR/untyped.after.json"

ruby skills/typing-ruby-files/scripts/generate_report.rb \
  --scope "$ARTIFACT_DIR/scope.json" \
  --before "$ARTIFACT_DIR/untyped.before.json" \
  --after "$ARTIFACT_DIR/untyped.after.json" \
  --steep "$ARTIFACT_DIR/steep.json" \
  --out-md "$ARTIFACT_DIR/report.md" \
  --out-json "$ARTIFACT_DIR/report.json"
```

If runtime `lib/**` code changed, include targeted test evidence:

```bash
bundle exec rspec spec/path/to/file_spec.rb 2>&1 | tee /tmp/full_rspec.log | grep -E 'Pending:|Failures:|Finished' -A 99
```

Pass targeted test metadata to report generation:

```bash
ruby skills/typing-ruby-files/scripts/generate_report.rb \
  ... \
  --runtime-lib-edit lib/datadog/core/metrics/client.rb \
  --targeted-tests-command "bundle exec rspec spec/datadog/core/metrics/client_spec.rb 2>&1 | tee /tmp/full_rspec.log | grep -E 'Pending:|Failures:|Finished' -A 99" \
  --targeted-tests-result pass
```

## References

- Read `references/typing_policy.md` for strict gates, transient comment format, and compromise schema.
- Read `references/evaluations.md` for required eval scenarios and regression loop.

## Validation

Run primary validation first when available:

```bash
skills-ref validate skills/typing-ruby-files
```

Run secondary local sanity validation:

```bash
python3 /Users/marco.costa/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/typing-ruby-files
```
