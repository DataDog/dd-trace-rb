# Case studies: how much work is an upgrade?

Read these when it's unclear from the lockfile diff whether the
integration still works after an upgrade. Both are real cases, and both
ended with an exception.

## mongo CVE-2026-88030 (PR #6303)

Advisory: GHSA-4ww7-gqv6-mffc, high, GridFS query-logic injection. Fixed
only in 2.26.0.

Why we didn't upgrade (neither reason was visible from the advisory):

1. Gemset `mongo-min` deliberately pins the oldest tested version.
   Upgrading it would remove the coverage it exists for.
2. The upgrade needed a newer MongoDB server image for tests (4.4) and a
   spec fix for a changed server error message.

Resolution: one `ignore` entry for the advisory id, because `mongo-min`
keeps a vulnerable version indefinitely. It can be removed once no
lockfile has `mongo` below 2.26.0.

Lesson: an upgrade can break the code, the tests, or the test
infrastructure. Both problems only showed up by running the tests.

## ruby_llm CVE-2026-67991

Advisory: GHSA-42r3-x6vx-x49x, high, ReDoS in `RubyLLM::Utils.underscore`
on Ruby 3.1.x, through crafted tool/agent class names.

Why we didn't upgrade: it is only fixed in `>= 2.0.0.rc1`, and there is no
stable 2.x release. The `ai_guard` integration doesn't support the 2.x API
(`RubyLLM::Content` was removed), and all 8 instrumentation specs failed
against 2.0.0.rc3.

Resolution: one `ignore` entry for the advisory id. It can be removed once
lockfiles can use a fixed `ruby_llm` (2.0.0+) and the integration supports
it.

Lesson: a fix only available as a prerelease doesn't count as available.
Counting the failing specs turned "probably breaks" into a clear decision.
