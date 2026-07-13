# OpenFeature agent guidance evals

These lightweight evals check that a Codex session started at the repository root recognizes `lib/datadog/open_feature/AGENTS.md` as governing guidance for FFE work.

The first phase covers awareness only. Separate cases verify the root route for changes under:

- `lib/datadog/open_feature/`;
- `spec/datadog/open_feature/`; and
- `sig/datadog/open_feature/`.

These cases do not evaluate whether the agent follows the scoped guide's content. Content-adherence evals are the next phase after discovery is reliable.

Run all cases from any directory in the checkout:

```bash
ruby tools/agent-evals/open_feature_guidance/run.rb
```

To compare discovery before and after a routing change, point the same cases at another checkout:

```bash
ruby tools/agent-evals/open_feature_guidance/run.rb --root /path/to/pre-change-checkout
```

Run one case or select a model:

```bash
ruby tools/agent-evals/open_feature_guidance/run.rb --case lib_awareness
ruby tools/agent-evals/open_feature_guidance/run.rb --model MODEL_ID
```

Each case launches a fresh, ephemeral, read-only `codex exec` session rooted at the repository. The runner asserts that both the root and scoped instruction files are identified, and writes no results into the checkout. It is intentionally not wired into CI or LLMObs yet.
