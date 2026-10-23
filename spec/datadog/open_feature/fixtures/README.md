# Experimentation opt-out policy cases

`experimentation-opt-out-policy.jsonl` contains all 90 `policy` cases from the
[shared Lean contract](https://github.com/DataDog/ffe-system-test-data/blob/f8a4176cd8360b12b56a8b6ec6ef215e2cc21077/contracts/experimentation-opt-out/corpus/browser-proposal.jsonl).

Source SHA256: `c4a1b9c9eed7197b8d66c1d3e46fcaaa4ec70143a2583b31baa04086c8f652dd`.
Extracted policy SHA256: `0d396beb2b627606f795386340d5e9d7443a40c51e84200b60527938969f7175`.

The cases cover D002, D004 revision 2, D010 for valid boolean input, and D011.
The adapter uses the production Ruby NativeEvaluator and C extension. It preserves every expected result.
Timestamp grammar, provider configuration, transport, and telemetry delivery are outside this profile.
