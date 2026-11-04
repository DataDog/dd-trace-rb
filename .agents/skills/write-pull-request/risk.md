# Assessing risk

The main question: does this change break something that users or other
systems already rely on, in code or in data, without a deprecation period?

## API: code users write against

- Public API: method signatures and configuration. A change in signature
  or behavior breaks callers when they upgrade.
- Constants: users reference them directly. Renaming them or changing
  their value breaks that code.
- Default configuration: changing a default changes behavior for every
  user who did not configure it.

## Data: what downstream consumers expect

- Values used as identifiers or grouping keys, for example the span
  `resource`. Users build monitors, alerts, and dashboards on exact
  values.
- Data schemas: a telemetry event that changes shape breaks whatever
  receives it.
- Data formats: other tracers read distributed tracing headers, so both
  the old and the new formats must stay readable.

Breaking data is the worst case. Consumers cannot opt out by not upgrading.
Nobody notices until wrong data has already been ingested.

## Security

- Metadata that may contain PII: HTTP headers carry credentials, and tag
  values can contain user data. Sending such metadata somewhere new can
  leak it.
- Sanitization and obfuscation: API keys must never be logged. Weakening or
  bypassing a scrubber is a leak.

## One-way or two-way door

One-way (cannot be undone): a released gem version, a shipped schema or
format, and data already sent. Everything else is two-way: say how to undo
it, for example revert, re-run, or restore the setting. If there is no way
to undo it, say so, that is the risk.

## Writing the section

Name what is affected concretely, for example "span resource values for
HTTP spans", not "low risk".
