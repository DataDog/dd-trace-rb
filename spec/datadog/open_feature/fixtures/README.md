# Experimentation opt-out policy cases

`experimentation-opt-out-policy.jsonl` contains all 90 `policy` cases from the
[shared Lean contract](https://github.com/DataDog/ffe-system-test-data/blob/f8a4176cd8360b12b56a8b6ec6ef215e2cc21077/contracts/experimentation-opt-out/corpus/browser-proposal.jsonl).

Source SHA256: `c4a1b9c9eed7197b8d66c1d3e46fcaaa4ec70143a2583b31baa04086c8f652dd`.
Extracted policy SHA256: `0d396beb2b627606f795386340d5e9d7443a40c51e84200b60527938969f7175`.

The cases cover these [policy definitions](https://github.com/DataDog/ffe-system-test-data/blob/f8a4176cd8360b12b56a8b6ec6ef215e2cc21077/contracts/experimentation-opt-out/browser-decisions.json):

- D002: distinguish an absent cutoff from a malformed cutoff; disabled mode ignores it.
- D004 revision 2: malformed activation produces a flag-wide error only for future mode with a valid cutoff.
- D010: classify allocations using an explicit boolean `doLog`; missing-field compatibility is outside this profile.
- D011: apply immediate exclusion or compare activation against the cutoff, then continue ordinary allocation order.

The adapter uses the production Ruby NativeEvaluator and C extension. It preserves every expected result.
Timestamp grammar, provider configuration, transport, and telemetry delivery are outside this profile.
