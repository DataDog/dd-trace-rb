# Dependency audit (bundler-audit)

The `bundler-audit` CI job scans appraisal lockfiles eligible for audit
(Ruby 3.1+). It fails the job for gems with high/critical CVE
advisories. It also fails for any advisory that the pinned scanner
cannot score. For example, a CVSS-v4-only advisory returns a `nil`
criticality, and the task treats it as a failure too.

The workflow skips the job on `master` pushes and `bump_to_version_*`
release PRs, because those lockfiles predate the advisory database
refresh.

The Gemfile does not include the task. You run it standalone via
`rake -f`. To reproduce locally, run:

```bash
.github/scripts/check/dependency_audit.sh
```

The script installs pinned gems and runs the audit task. The output
prints a summary, the fix instructions, and a table with every finding
(lockfile, gem, version, advisory id). The task also writes the
findings to `tmp/dependency_audit_findings.json`.

## If the audit fails

1. Run `BUNDLE_GEMFILE=<affected gemfile> bundle update GEM_NAME` (or `bundle lock --update GEM_NAME`) to move the flagged gem to a patched version. Plain `bundle exec rake dependency:lock` will not move the version on its own.

2. If no patched version exists for the Ruby/framework constraint in
   that appraisal, document the exception in `.bundler-audit.yml`:
   - Use `ignore_gem_versions` first. It covers only the exact pinned
     gem and version. When you later bump the gem, the finding
     reappears instead of staying silently hidden.
   - Use the top-level `ignore` list (by advisory id) only as a last
     resort. It suppresses the advisory for any gem and version.
   - Every entry must include a reason that names what pins the gem and why you cannot upgrade it.

For full triage guidance (blast radius, CVE research, upgrade or
exception), see the `handle-cve` skill in `.agents/skills/handle-cve/`.
