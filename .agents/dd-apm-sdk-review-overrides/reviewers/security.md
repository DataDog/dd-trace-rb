Override for `reviewers/security.md` (in the core skill folder) — read that file first, then this.

# Security — dd-trace-rb specifics

This file starts with one confirmed pattern and should grow — add the next
one you learn from review. Do not treat it as exhaustive.

[`AGENTS.md` § "Ask First"](../../../AGENTS.md) already forbids storing sensitive data or PII in data structures, arguments, or logs. This override names the concrete shapes that show up in this gem.

## Secrets must not become span tags or log lines

Never write credentials into a span tag, a metric, or a log line:

- `Datadog.configuration.api_key` / `cfg.api_key` / `DD_API_KEY` / `DD_APP_KEY`
- A DSN or URL with an embedded username and password
- `Authorization`, `Cookie`, or other credential-bearing headers

`span.set_tag('api_key', cfg.api_key)` and `Datadog.logger.debug("connecting with api_key=#{cfg.api_key}")` are the same finding: the secret leaves the process and becomes customer-visible. Treat it as **P0**.

Request bodies, query strings, and other PII follow [`AGENTS.md` § "Ask First"](../../../AGENTS.md): proceed only with explicit human approval. Without approval, writing them into a tag, metric, or log is **P0**. With approval, do not report a P0 for that approved PII — still flag any credential that rode along.

Safe alternatives: tag the host / port / scheme only. Do not log the raw value "at debug, it's fine" — debug logs ship.

Look for this around contrib connect / authenticate / client-init paths (`lib/datadog/tracing/contrib/**`, `lib/datadog/appsec/contrib/**`) and anything that reads configuration.
