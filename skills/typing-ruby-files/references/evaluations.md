# Evaluations

## Contents

1. Eval 1: straightforward static file
2. Eval 2: dynamic/metaprogramming-heavy file
3. Eval 3: transient steep/rbs limitation
4. Regression rule

## Eval 1: straightforward static file

Target profile:

- One small Ruby file with mostly explicit control flow and data shapes.
- Matching signature exists and already passes basic steep checks with mild precision gaps.

Expected output quality:

1. Remove avoidable `untyped`.
2. Keep method arity, keywords, and return types precise and aligned with Ruby behavior.
3. Avoid runtime behavior changes unless needed for typing correctness.

Expected report contents:

1. No stale paths and no missing signatures.
2. Positive `untyped` delta (or zero with strong justification).
3. Both steep commands pass.
4. Complete residual `untyped` inventory with file:line evidence.

## Eval 2: dynamic/metaprogramming-heavy file

Target profile:

- File uses runtime method generation, dynamic dispatch, or DSL-style constructs.
- Signature precision is possible only up to a containment boundary.

Expected output quality:

1. Contain dynamic edges narrowly; avoid broad type erasure.
2. Prefer interfaces/type aliases/unions over blanket `untyped`.
3. Document why remaining dynamic boundaries cannot be narrowed now.

Expected report contents:

1. Explicit compromise entries for each remaining dynamic gap.
2. Diagnostic evidence when available, otherwise explicit `no direct diagnostic`.
3. Concrete follow-up refactor guidance for non-transient debt.

## Eval 3: transient steep/rbs limitation

Target profile:

- Typing gap likely caused by analyzer or type-system limitation.
- Local refactor would be high-risk or disproportionately invasive.

Expected output quality:

1. Add inline transient comment in affected Ruby/RBS location.
2. Include Steep issue link first, then RBS issue link if needed.
3. Include explicit removal condition.

Expected report contents:

1. Compromise entry tagged as transient with upstream link.
2. If no issue exists, include text:
   `no known upstream issue as of YYYY-MM-DD` using execution date.
3. Clear explanation of why the gap is transient and not refactorable now.

## Regression rule

1. Re-run all three evals after any non-trivial skill script or instruction change.
2. Treat regressions as blocking until deterministic behavior is restored.
3. Keep expected report structure stable across runs for reproducibility.
