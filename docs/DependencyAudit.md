# Dependency audit (bundler-audit)

The `bundler-audit` CI job scans appraisal lockfiles eligible for audit
(Ruby 3.1+). It fails the job for gems with high/critical CVE
advisories. It also fails for any advisory the pinned scanner cannot
score. For example, a CVSS-v4-only advisory comes back with a `nil`
criticality, and is treated as failing too.

The job is skipped on `master` pushes and `bump_to_version_*` release
PRs, since those ship lockfiles that predate the advisory database
refresh.

The task is intentionally not part of the bundle. It runs standalone
via `rake -f`. To reproduce locally, run:

```bash
.github/scripts/check/dependency_audit.sh
```

The script installs pinned gems and runs the audit task. The output
prints a summary, the fix instructions, and a table with every finding
(lockfile, gem, version, advisory id). The same findings are also
written to `tmp/dependency_audit_findings.json`.

## If the audit fails

1. Preferred fix: `BUNDLE_GEMFILE=<affected gemfile> bundle update GEM_NAME` (or `bundle lock --update GEM_NAME`) to upgrade the flagged gem to a patched version. Plain `bundle exec rake dependency:lock` will not move the version on its own.

2. If no patched version exists for the Ruby/framework constraint in
   that appraisal, document the exception in `.bundler-audit.yml`:
   - Prefer `ignore_gem_versions`. It is scoped to the exact pinned
     gem+version. When you later bump the gem, the finding reappears
     instead of staying silently hidden.
   - Use the top-level `ignore` list (by advisory id) only as a last
     resort. It suppresses the advisory for any gem/version.
   - Every entry must include a reason explaining what pins the gem and why it cannot be upgraded.

For full triage guidance (blast radius, CVE research, upgrade vs
exception), see the `handle-cve` skill in `.agents/skills/handle-cve/`.
