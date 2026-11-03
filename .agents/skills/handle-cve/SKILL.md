---
name: handle-cve
description: 'Use when the dependency audit goes red — `.github/scripts/check/dependency_audit.sh` or the bundler-audit CI job — or when a newly published CVE/GHSA on a dependency gem blocks a PR.'
---

# Handling a CVE that blocks CI (bundler-audit)

Goal: make the failing dependency audit pass. Run the audit locally,
research the CVE, decide on a fix, and validate it before pushing. CI runs
the same audit afterwards.

## 1. Who handles it, and how urgently

Whoever hits the failing audit handles it, locally or on a PR. There is no
security on-call, this is routine maintenance.

The audit protects the machines that install and run the gems under
`gemfiles/` (developer machines and CI), not the shipped gem. The `datadog`
gem declares its runtime dependencies as version ranges, so customers
choose which versions they install. We only control what we install
ourselves.

Priority:

1. The advisory is about a compromised or malicious package, or the
   vulnerable code runs during our tests: tell the maintainers, and remove
   the gem from the lockfiles.
2. The audit fails on `master` or a shared branch: confirm locally, and fix
   it the same day as described below.
3. The audit fails only on your branch: fix it before opening the PR, the
   same way, but branch off your branch and merge the fix into your PR.

When the audit fails on `master` (and therefore on every open PR):

1. Branch off the latest `master`.
2. Follow sections 2 to 5.
3. Open a draft PR and get it merged quickly.
4. Other PRs merge the updated `master` and pass again.

## 2. Find the affected gems, lockfiles, and tests

Run the audit. It checks every covered lockfile, so one container is
enough. `docs/DependencyAudit.md` describes what the audit covers and which
advisories make it fail.

The audit script installs its own pinned gems and doesn't need a bundle. It
writes a findings JSON file only on failure, and the command below prints
it, since the file stays inside the container. Each finding lists the
advisory id, the gem and version, the severity, and the lockfile.

```bash
docker compose run --rm tracer-4.0 sh -c \
  '.github/scripts/check/dependency_audit.sh || cat tmp/dependency_audit_findings.json'
```

All commands in this skill run in the containers from `docker-compose.yml`.
Each `tracer-X.Y` service uses one Ruby version and its own default Gemfile.

Then find which tests use each affected lockfile, using the `Matrixfile`.
This can include more Ruby versions than the audit covers: a Ruby version
the audit skips still runs the gem, so an upgrade can break it there, even
though it never makes the audit fail.

1. The lockfile name contains the gemset:
   `ruby_3.3_mongo_latest.gemfile.lock` is gemset `mongo-latest`
   (underscores become hyphens in the `Matrixfile`).
2. Find the gemset in the `Matrixfile`. The entry gives the rake task and
   the Ruby versions it runs on.
3. A gem can have several gemsets. `mongo` also has `mongo-min`, which pins
   the oldest tested version. Both map to `test:mongodb`, so one advisory
   can affect two lockfiles per Ruby version.

```ruby
"mongodb" => {
  "mongo-latest" => "✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ 3.4 / ✅ 4.0",
  "mongo-min"    => "✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ 3.4 / ✅ 4.0",
},
```

At the end of this step you should know:

- which advisory affects which gem, at which versions
- which lockfiles contain those versions
- which rake tasks install and run the gem, and on which Ruby versions

## 3. Research the CVE

Research only until you can answer the questions below, more doesn't
change the decision.

1. Read the advisory: the GHSA entry on github.com/advisories, or the CVE
   record. It has the description, the affected versions, and the patched
   versions. Read it on the web, the audit's copy of ruby-advisory-db is
   recreated inside the container on each run.
2. The gem's repository has the changelog, the upstream issue, and the fix
   commit.
3. Check that the patched version supports every Ruby version from step 2:
   `gem specification -r -v VERSION GEM required_ruby_version`. If it
   requires a newer Ruby than one the audit covers, that lockfile can't be
   upgraded and needs an exception, while the others are upgraded. If the
   unsupported Ruby isn't covered by the audit, that lockfile simply stays
   on the old version.

Example advisory, for the mongo case above:

```yaml
---
gem: mongo
cve: 2026-88030
ghsa: 4ww7-gqv6-mffc
title: Improper neutralization of special elements in data query
  logic in the GridFS component
cvss_v3: 8.3
patched_versions:
  - ">= 2.26.0"
related:
  url:
    - https://github.com/advisories/GHSA-4ww7-gqv6-mffc
```

At the end of this step you should know:

- What is vulnerable: the component, the kind of bug, and what an attacker
  needs to control.
- Whether it is exploited in the wild.
- How serious it is for us: the CVSS vector, and whether the vulnerable
  code runs in our tests.
- Which versions fix it, and whether that is a new major version.
- Whether the fix can be installed on all the Ruby versions from step 2.

Summarize in one sentence: what is vulnerable, what fixes it, and what the
fix requires in this repo.

## 4. Decide how to unblock

Making the audit pass is urgent. Removing the vulnerable version can come
later if it is a lot of work.

For each lockfile, there are two options:

1. Upgrade the lockfile to a patched version. This both unblocks and fixes.
   Small fixes needed for the integration go in the same change.
2. Add an exception: keep the vulnerable version and add a documented
   entry in `.bundler-audit.yml` to ignore the finding, plus a follow-up
   issue for the real fix. An entry ignores either a whole advisory id, or
   one exact gem version.

Exceptions are not allowed for case 1 of section 1 (a malicious package, or
vulnerable code that runs in our tests): the gem must be removed from the
lockfiles.

For each affected lockfile:

```text
Can this lockfile use a patched version (on its Ruby version, and within
the gemset's constraints)?
├─ yes → update the lockfile and run the tests from step 2:
│      ├─ pass → upgrade
│      ├─ fail, small fix → upgrade, with the fix in the same change
│      └─ fail, large fix → revert the lockfile, keep the vulnerable version
└─ no → keep the vulnerable version

Then add an exception for the kept versions:
├─ one version → one `ignore_gem_versions` entry
└─ several versions, and upgrades can't reduce them → one `ignore` entry
   for the advisory id
```

To update a lockfile, use the container matching its Ruby version:

```bash
docker compose run --rm -e BUNDLE_GEMFILE=gemfiles/<affected>.gemfile \
  tracer-<RUBY> bundle lock --update GEM_NAME
```

This only changes the lockfile, without installing the gem (unlike
`bundle update GEM_NAME`).

To run the tests:

```bash
docker compose run --rm tracer-<RUBY> bundle exec rake test:<TASK>
```

To add an exception, add the entry to `.bundler-audit.yml`, following the
existing entries. Each entry documents the advisory id, the gem and exact
version, why it can't be upgraded, when the entry can be removed, and the
follow-up issue if the fix is deferred.

If it's unclear how much work an upgrade is, read `CASE-STUDIES.md`: two
real cases where the blocker was a deliberately pinned gemset, the test
infrastructure, or a fix only available as a prerelease.

This step is done when every lockfile from step 2 is either upgraded or
kept with its vulnerable version recorded in the narrowest possible
exception.

## 5. Validate and ship

Run every command in a `tracer-X.Y` container.

- If a lockfile changed, run `bundle exec rake dependency:checksum_coverage`.
  Rewriting a lockfile can drop its `CHECKSUMS` section, and this task
  catches that.
- If the gem version changed, run the tests from step 2 on the oldest and
  newest Ruby versions among the lockfiles that changed. With a partial
  upgrade, the oldest Ruby in the matrix might not use the new version at
  all.
- Re-run the audit. It must print `No high or critical advisories found.`
  This also validates any `.bundler-audit.yml` changes.

Ship:

- No changelog fragment, this is internal tooling.
- Never commit on `master`. Open a draft PR with the `AI Generated` label
  and a `chore(security): ...` title.
- The PR description gives the advisory id, the affected lockfiles, the
  decision, and the follow-up issue for deferred work. For exceptions, it
  also says when they can be removed.

## Never do this

These mistakes can't be fixed by a later commit:

- Never edit files under `gemfiles/` by hand, they are generated by
  Bundler. Use `bundle lock --update`. A hand-edited lockfile can resolve
  differently from what Bundler would produce.
- Never add an exception for a malicious package or for vulnerable code
  that runs in our tests. Tell the maintainers first. An exception would
  hide an active compromise on the machines running the tests.
