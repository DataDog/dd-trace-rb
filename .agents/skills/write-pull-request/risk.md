# Categorizing risk

The question behind every Risk field: does this change alter anything an
external party already depends on? In code or in data, without a
versioned deprecation path?

## API contract: users write code against these

- Public API: method signatures and the configuration interface.
  Callers cannot see the diff. A signature or behavior change breaks
  them at upgrade.
- Constants: users reference them directly. Renames and value changes
  break requires.
- Default configuration: flipping a default changes behavior for
  every user who never wrote a line of config.

## Data contract: downstream consumers expect these

- Field values that act as identifiers or grouping keys. For example,
  the span `resource`: users build monitors, alert rules, and
  dashboards in the Datadog backend on exact values.
- Data schemas: receivers expect a schema. A telemetry event that
  changes shape breaks the receiving pipeline.
- Data formats: receivers expect a format. Distributed tracing headers
  interoperate with other tracers, so both old and new forms must be
  readable.

A data contract break is the worst kind: unilateral, asynchronous, and
silent. The consumer never upgrades. They get wrong data, and both
old and new data are already ingested by the time anyone notices.

## Security: trust boundaries

- Metadata that may carry PII. HTTP headers carry authentication
  material, and tag values can embed user data. New propagation of
  such data is a leak risk.
- Sanitization and obfuscation paths. API keys must never be logged. A
  change that weakens or bypasses a scrubber is a leak.

## Door type

One-way: a published gem version, a shipped schema or format, and data
already emitted, which cannot be unsent. Everything else is two-way:
name the mechanical undo, such as revert, re-run, or restore the
setting. If no undo can be named, that absence is the risk. Say so.

## Writing the field

Name the concrete scope, such as "span resource values for HTTP
spans," never a vague adjective like "low risk."
