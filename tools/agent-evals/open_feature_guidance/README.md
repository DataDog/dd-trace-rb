# OpenFeature agent guidance evals

These lightweight evals check that a Codex session started at the repository root recognizes `lib/datadog/open_feature/AGENTS.md` as governing guidance for OpenFeature work.

The first phase covers awareness only. Separate cases verify the root route for changes under:

- `lib/datadog/open_feature/`;
- `spec/datadog/open_feature/`; and
- `sig/datadog/open_feature/`.

These cases do not evaluate whether the agent follows the scoped guide's content.

## RuboCop adherence

The writable lint eval verifies more than awareness:

```bash
ruby tools/agent-evals/open_feature_guidance/run_lint.rb
```

It creates a temporary detached worktree, installs an eval-only subset of the forthcoming [RuboCop configuration from #6032](https://github.com/DataDog/dd-trace-rb/pull/6032), and asks a fresh Codex session to make a small OpenFeature change. The case passes only when the Codex JSON trace contains a RuboCop command, an independent RuboCop post-check reports no offenses, the requested change is present, and no unrelated files changed.

The fixture starts with a double-quoted string while the configuration requires single quotes. A minimal string-value edit therefore cannot pass accidentally. RuboCop remains the executable source of truth; the agent guidance names the workflow without duplicating individual cops.

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
