# Security & Safety

Secrets and sensitive configuration, CI and supply chain, PII, and safety inside customer processes.

**When planning:** take the rules below into account when designing the change.

**When reviewing:** also inspect commit messages and the PR description. Report a finding when the diff matches a rule's `Flag:` line, or when it has a clear security or safety problem that no rule covers (mark it `no rule`), with the leak path (source to sink).

The GitHub Actions security rules in [AGENTS.md](../../../../AGENTS.md#github-actions) also apply.

## 1. Sensitive data

### SEC-1.1: Never write API keys, auth headers, or whole request headers or metadata to logs, span tags, or telemetry
- Flag: a logger, `set_tag`, or telemetry argument holding an API key, a `DD-API-KEY` or `Authorization` value, a full headers hash, a Rack `env`, or an `inspect` of a request or response.
- Not when: a customer opt-in feature built for it collects the data (for example, configured header tagging), with its documented redaction.
- ❌ `Datadog.logger.debug { "Agentless request: #{request.each_header.to_h}" }`
- ✅ `Datadog.logger.debug { "Agentless request to #{uri.host} failed with #{response.code}" }`

### SEC-1.2: Don't weaken, bypass, or narrow an existing scrubber
- Flag: a change that removes entries from a redaction or obfuscation list, adds a path that skips it (for example, DI values serialized without `redactor.redact_identifier?`/`redact_type?`, or a URL or query tagged without the quantization/obfuscation step), or loosens an obfuscation pattern. See [risk.md](../../write-pull-request/risk.md#security).

### SEC-1.3: Treat sending headers, tag values, or captured data to a new destination as a new exposure
- Flag: span metadata, HTTP headers, or user-controlled values newly sent to another sink (a telemetry field, an agentless endpoint, a log line, a new span event) without the scrubbing the existing sink applies. See [risk.md](../../write-pull-request/risk.md#security).

## 2. Dependencies and supply chain

### SEC-2.1: Run `bundle audit` before any `bundle install` or bundle cache restore
- Flag: a CI job that audits dependencies after `bundle install`, `bundler-cache: true`, or a cache restore, or an audit job that other bundle-installing jobs don't `needs:`. Install-time native code can subvert a later audit. See [DependencyAudit.md](../../../../docs/DependencyAudit.md).

### SEC-2.2: Audit between `bundle lock --update` and `bundle install`, and enforce a dependency-age cooldown
- Flag: automation that updates committed lockfiles and installs them with no audit in between, or with no minimum dependency age check.

### SEC-2.3: Keep and verify `CHECKSUMS` entries in lockfiles
- Flag: a lockfile rewrite that drops its `CHECKSUMS` section (run `bundle exec rake dependency:checksum_coverage`), or a check that looks for the section header without verifying the required entries.

### SEC-2.4: Never edit lockfiles by hand
- Flag: `gemfiles/*.lock` or `Gemfile.lock` changes that don't match what Bundler produces, such as a version edited without its dependencies or checksum. Use `bundle lock --update`, and `bundle exec rake dependency:generate` for `.gemfile` files. See [handle-cve](../../handle-cve/SKILL.md#never-do-this).

### SEC-2.5: Scope `.bundler-audit.yml` exceptions narrowly and justify them
- Flag: a new top-level `ignore` (advisory-wide) entry where `ignore_gem_versions` would cover the pinned version, an entry without a reason naming what pins the gem, or any exception for a malicious package or for vulnerable code that runs in tests. See [DependencyAudit.md](../../../../docs/DependencyAudit.md#if-the-audit-fails).
- ❌ `ignore: [CVE-2026-12345]` with no comment
- ✅ `ignore_gem_versions: [{gem: rack, version: 1.6.13, reason: "Pinned by devise_min/rack_1 Gemfiles' rack-1.x constraints"}]`

## 3. CI and release

### SEC-3.1: Never merge system-tests pins to unmerged commits
- Flag: `SYSTEM_TESTS_REF` in `.gitlab-ci.yml`, or the system-tests `ref:`/`uses:` lines in `.github/workflows/system-tests.yml`, pointing at a commit not on `DataDog/system-tests` `main`. See [AGENTS.md](../../../../AGENTS.md#system-tests-commit-sha-updates).

## Don't flag
- Removing the catch-all `*` rule from `CODEOWNERS` when explicit owners and the merge-gate ownership check cover the files.
