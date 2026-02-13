# Typing Policy

## Contents

1. Scope gates
2. Mandatory checks
3. Transient-gap comment rules
4. Compromise reporting schema
5. Report completeness checklist

## Scope gates

1. Accept only a small target list under `lib/**/*.rb`.
2. Detect stale paths first.
3. For each existing target, require mapped `sig/**/*.rbs` path:
   `lib/path/file.rb` -> `sig/path/file.rbs`.
4. Fail if any target is stale or any mapped signature is missing.
5. Keep work limited to the resolved scope unless diagnostics prove a cross-file typing dependency.

## Mandatory checks

1. Before edits, capture `untyped` inventory in mapped signatures.
2. After edits, capture inventory again and compute delta.
3. Run both:
   `bundle exec steep check <scope>`
   `bundle exec steep check --severity-level=information <scope>`
4. If any `lib/**` runtime code changed, run targeted behavior tests and capture output with:
   `2>&1 | tee /tmp/full_rspec.log | grep -E 'Pending:|Failures:|Finished' -A 99`
5. Do not mark the work complete without report artifacts that include:
   `scope.json`, `untyped.before.json`, `untyped.after.json`, `steep.json`, and final report files.

## Transient-gap comment rules

Apply this only when the gap is likely a Steep/RBS limitation, not a local refactorable design issue.

Comment requirements in affected Ruby/RBS code:

1. State transient rationale.
2. Include upstream issue link.
3. State explicit removal condition.

Issue lookup order:

1. Steep search:
   `https://github.com/soutaro/steep/issues?q=is%3Aissue%20MY_TEXT`
2. RBS search:
   `https://github.com/ruby/rbs/issues?q=is%3Aissue%20MY_TEXT`

If no relevant issue exists, include:

`no known upstream issue as of YYYY-MM-DD`

Use the current execution date for `YYYY-MM-DD`.

Do not classify a gap as transient when a reasonable refactor can remove it. Report the required refactor as actionable debt instead.

## Compromise reporting schema

For each remaining typing compromise, report all fields:

```json
{
  "offence": "what typing gap remains",
  "cause": "why the gap exists",
  "chosen_solution": "containment now + follow-up action",
  "evidence": {
    "file": "path/to/file.rbs",
    "line": 123,
    "diagnostic_id": "Ruby::SomeDiagnostic",
    "message": "diagnostic message text"
  }
}
```

If no direct steep diagnostic exists, set:

```json
{
  "evidence": "no direct diagnostic"
}
```

Also include complete post-edit file:line inventory of all remaining `untyped` in scope.

## Report completeness checklist

1. Stale-path check result.
2. Mapping check result (`lib` <-> `sig`).
3. `untyped` before/after totals and delta.
4. Full post-edit `untyped` file:line inventory.
5. Steep results for normal and information severity.
6. Targeted test command and result if runtime `lib/**` changed.
7. Compromise entries with offence/cause/chosen_solution/evidence.
