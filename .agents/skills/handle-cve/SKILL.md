---
name: handle-cve
description: 'Use when the dependency audit goes red — `rake dependency:audit` or the bundler-audit CI job — or when a newly published CVE/GHSA on a dependency gem blocks a PR.'
---

# Handling a CVE that blocks CI (bundler-audit)

Goal: turn the red audit task green, locally. Run the audit on your
machine, research the CVE, triage the impact, decide the fix, and
validate before you push. CI runs the same audit later and only
confirms what you already saw.

## 1. Role and priority

The owner is whoever hits the red audit, locally or on a PR. There
is no security on-call. This is routine maintenance. The whole purpose
of the audit is supply-chain health: the gems under `gemfiles/` get
installed and run, locally and in CI. We protect the machines that run
the audit and the test suite, not the shipped gem. The `datadog` gem
declares its runtime dependencies as version ranges. Each customer
picks the versions that install, so we control only what we install
ourselves.

Priority:

1. The advisory is supply-chain (a compromised or malicious package),
   or the vulnerable code runs during our tests. Tell the maintainers,
   and get the gem off the lockfiles.
2. The audit fails on `master` or a shared branch. Run it locally
   to confirm. Unblock the same day, with the loop below.
3. The audit fails only in your branch. Fix it before you open the PR.
   Same loop, but branch off your branch, and merge into your PR.

The unblock loop:

```text
red audit on master, and on every open PR
→ branch off the latest master
→ run sections 2 to 5
→ fast draft PR, merge
→ other PRs merge the updated master, and turn green
```

## 2. Identify the CVE and its blast radius

Run the audit. It scans every covered lockfile, so one container is
enough. `docs/DevelopmentGuide.md#dependency-audit-bundler-audit` is
authoritative on what the job covers and which advisories fail it.

The findings JSON is written only on failure, and the command below
prints it because the file stays in the container's `tmp/` volume.
Each entry gives the advisory id, the gem and version, the
criticality, and the lockfile.

```bash
docker compose run --rm tracer-4.0 sh -c \
  'bundle exec rake dependency:audit || cat tmp/dependency_audit_findings.json'
```

Every command in this skill runs inside the containers from
`docker-compose.yml`. Each `tracer-X.Y` service pins one Ruby and
its own default Gemfile.

To map the blast radius, walk each finding from the lockfile to the
tests that run it, through the `Matrixfile`. The blast radius is the
full matrix a gemset covers, which runs wider than audit coverage: an
unaudited Ruby still runs the gem, so an upgrade can break it, but it
never turns the audit red on its own.

1. The lockfile name carries the gemset:
   `ruby_3.3_mongo_latest.gemfile.lock` is gemset `mongo-latest`.
   Underscores in the file name become hyphens in the `Matrixfile`.
2. Open the `Matrixfile` and find the gemset. The entry names the
   rake task and the Rubies it covers.
3. A gem can have more than one gemset. `mongo` also has
   `mongo-min`, which pins the oldest tested driver. Both gemsets
   map to `test:mongodb`, so one advisory can hit two lockfiles per
   Ruby.

```ruby
"mongodb" => {
  "mongo-latest" => "✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ 3.4 / ✅ 4.0",
  "mongo-min"    => "✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ 3.4 / ✅ 4.0",
},
```

After this section you must be able to answer:

- Which advisory hits which gem, at which pinned versions?
- Which lockfiles pin those versions?
- Which rake tasks install and run the affected gem, and on which
  Rubies?

Section 4 picks the lockfiles to update from these answers. Section
5 runs the tasks from these answers, on the earliest and the latest
Ruby.


## 3. Research the CVE

Goal: turn the advisory id from section 2 into the facts that
section 4 needs to pick a resolution path. Research stops when the
questions below have answers. More depth does not change the
decision.

Process:

1. Read the advisory record: the GHSA entry at github.com/advisories,
   or the CVE record. It carries the description, the affected
   range, and the patched versions. The audit's ruby-advisory-db
   clone lives inside the container, and a new run recreates it.
   Read the record from the web.
2. The gem's own repository adds the changelog entry, the upstream
   issue, and the fix commit.
3. Check the patch against our constraints: the patched version's
   `required_ruby_version` against every Ruby in the blast radius
   (`gem specification -r -v VERSION GEM required_ruby_version`). A
   floor above an audited Ruby splits the lockfiles: that one cannot
   take the patch and needs an exception entry, while the rest
   upgrade. A floor above an unaudited Ruby only limits how far the
   fix reaches, since that lockfile had no finding to clear.

Example advisory record, the mongo case from section 2:

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

After this section you must be able to answer:

- What is vulnerable: the component, the bug class, and what an
  attacker must control.
- Is it exploited in the wild?
- How dangerous is it for us: the CVSS vector, plus whether the
  vulnerable component runs in the blast radius tasks.
- What fixes it: the patched versions, and is it a breaking major?
- Can we install the fix on the Rubies in the blast radius?

Close with one sentence: what is vulnerable, what fixes it, and
what the fix requires of this repo.

## 4. Decide how to unblock

Separate two jobs. The **unblock** turns the audit green and is due
now. The **fix** removes the vulnerable code and can be due later.

Two outcomes exist, per lockfile:

1. Upgrade: the lockfile moves to a patched version, so the unblock
   and the fix are the same change. Small breakage in the integration
   rides along in it.
2. Exception: the lockfile keeps the vulnerable pin, and a documented
   `.bundler-audit.yml` entry suppresses the finding. The entry is the
   unblock; a follow-up issue carries the fix. The entry takes one of
   two forms: the entire advisory id, or one exact gem and version.

Ship the unblock by the fastest safe path, and let a large fix follow
on its own schedule. The one case with no exception is section 1 case
1 — a supply-chain advisory, or vulnerable code that runs in our
tests — which needs the gem gone from the lockfiles.

Decision tree. Walk every affected lockfile:

```text
Can this lockfile take a patched version?
│  The patch must resolve on the lockfile's Ruby, and inside the
│  appraisal constraints.
├─ yes → lock the update, then ask:
│      Does the integration survive the update?
│      │  Run the task from the blast radius.
│      ├─ passes → upgrade
│      ├─ fails, fix is small → upgrade, with the fix in the same change
│      └─ fails, fix is large → revert the lockfile, keep the
│         vulnerable pin
└─ no → keep the vulnerable pin

Every kept pin is the exception. Collect the versions left:
├─ one version left → one `ignore_gem_versions` entry
└─ many versions left, and no upgrade can shrink them → one
   advisory-id `ignore` entry
```

To lock the update, use the container whose Ruby matches the
lockfile:

```bash
docker compose run --rm -e BUNDLE_GEMFILE=gemfiles/<affected>.gemfile \
  tracer-<RUBY> bundle lock --update GEM_NAME
```

This command changes only the lockfile. It does not install the
gem. `bundle update GEM_NAME` writes the same lockfile, but it
also installs the gem.

To run the blast-radius task:

```bash
docker compose run --rm tracer-<RUBY> bundle exec rake test:<TASK>
```

To record the exception, write the entries in `.bundler-audit.yml` and
land them. The tree above picks the form; the existing entries in that
file show the shape. Every entry documents the advisory id, the gem and
exact version, why it cannot upgrade, the removal conditions, and the
follow-up issue if the fix is deferred.

For sizing an upgrade when the lockfile diff does not settle it, read
`CASE-STUDIES.md`: two real advisories where the blocker was a
deliberately pinned gemset, the test infrastructure, or a patch that
shipped only as a prerelease.

Section 4 is done when every lockfile from section 2 has a verdict —
upgraded, or kept with its vulnerable version recorded — and the kept
versions are collected into the narrowest entry form that covers them.

## 5. Validate and ship

Run every command in a `tracer-X.Y` container, per section 2.

Validate what you changed:

- Lockfile changed: `bundle exec rake dependency:checksum_coverage`.
  A lockfile rewrite can drop its `CHECKSUMS` section, which pins
  the content digest of every gem. This task catches the loss.
- `.bundler-audit.yml` changed:
  `bundle exec rspec spec/tasks/dependency_audit_spec.rb`
- Gem version changed: run the blast-radius task in the containers of
  the earliest and the latest Ruby among the lockfiles that actually
  moved. A partial upgrade leaves the others on the old version, so
  the matrix's earliest Ruby may not run the new gem at all.

Then re-run the audit. It must print `No high or critical
advisories found.`

Ship:

- No changelog fragment. Internal tooling.
- Never commit on `master`. Draft PR, `AI Generated` label, title
  `chore(security): ...`.
- The PR states the advisory id, the affected lockfiles, the
  decision, and the follow-up issue for deferred work. Ignore
  entries also state their removal conditions.

## Hard guardrails

Two failures are unrecoverable by a later commit, so they get a stop
rather than a rule:

- Every file under `gemfiles/` is Bundler's output. Regenerate it with
  `bundle lock --update`; a hand edit produces a lockfile that resolves
  differently from the one Bundler would write.
- A supply-chain advisory, or one reachable in our tests, goes to the
  maintainers before anything else. An ignore entry here hides a live
  compromise on the machines running the suite.
