# OpenFeature agent guidance evals

These lightweight evals check that a Codex session started at the repository root follows the root `AGENTS.md` route into `lib/datadog/open_feature/AGENTS.md`.

The initial cases verify that the agent:

- maps `Datadog::OpenFeature::FlagEvaluation::BatchEncoder` to underscored production, spec, and signature paths; and
- carries the scoped guide's APM customer and architecture checks into its pre-review plan.

Run all cases from any directory in the checkout:

```bash
ruby tools/agent-evals/open_feature_guidance/run.rb
```

Run one case or select a model:

```bash
ruby tools/agent-evals/open_feature_guidance/run.rb --case constant_path
ruby tools/agent-evals/open_feature_guidance/run.rb --model MODEL_ID
```

Each case launches a fresh, ephemeral, read-only `codex exec` session rooted at the repository. The runner performs deterministic assertions against the structured final response and writes no results into the checkout. It is intentionally not wired into CI or LLMObs yet.
