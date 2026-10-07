# Case studies: sizing an upgrade

Read these when the decision tree asks whether the integration survives
an upgrade, and the answer is not obvious from the lockfile diff. Both
cases are real, and both ended in an exception.

## mongo CVE-2026-88030 (PR #6303)

Advisory: GHSA-4ww7-gqv6-mffc, high, GridFS query-logic injection.
Patched in 2.26.0 only.

Why no upgrade: two blockers, neither visible from the advisory.

1. Gemset `mongo-min` pins the oldest tested driver on purpose. Bumping
   it deletes the coverage the gemset exists to provide.
2. The upgrade needed a new MongoDB test server image (4.4) and a spec
   fix for a changed server error message.

Resolution: one advisory-id `ignore` entry covered every pin, because
`mongo-min` keeps a vulnerable version indefinitely and no upgrade
shrinks the set. Removal condition: no lockfile resolves a `mongo`
below 2.26.0.

The lesson that generalizes: a gem upgrade can break production code,
the tests, or the test infrastructure. Both blockers only surfaced by
running the blast-radius task.

## ruby_llm CVE-2026-67991

Advisory: GHSA-42r3-x6vx-x49x, high, ReDoS in
`RubyLLM::Utils.underscore` on Ruby 3.1.x, reachable via crafted
tool/agent class names.

Why no upgrade: fixed only in `>= 2.0.0.rc1`, and no 2.x stable release
exists. The `ai_guard` integration does not support the 2.x API —
`RubyLLM::Content` was removed, which produced 8/8 instrumentation spec
failures against 2.0.0.rc3.

Resolution: advisory-id `ignore`. Removal condition: lockfiles can
resolve a fixed `ruby_llm` (2.0.0+) and the integration supports it.

The lesson that generalizes: a patched version that exists only as a
prerelease is not an available fix. Counting the spec failures is what
turned "probably breaks" into a sized decision.
