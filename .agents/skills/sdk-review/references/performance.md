# Performance

Allocations and CPU cost on hot paths (span creation and finish, tagging, propagation, instrumentation callbacks), at startup, and in tooling.

**When planning:** take the rules below into account when designing the change.

**When reviewing:** report a finding when the diff matches a rule's `Flag:` line on a hot, startup, or high-volume path. Cite the rule ID and say which path it is on.

## 1. Hot paths

### PERF-1.1: Don't add a per-span callback to handle a per-trace concern
- Flag: a `span_before_finish`/`span_finished` subscriber (or similar per-span hook) that runs on every span to act on one, such as the root span. Use a per-trace event, or include a benchmark on a high-span-count trace.

### PERF-1.2: Don't allocate on rejection or no-op paths
- Flag: a hot-path method that allocates an Array, Hash, Struct, or String on every call, including the common rejected, sampled-out, or disabled case.
- ❌ `return [false, :rate_limited] unless bucket.take`
- ✅ `return :rate_limited unless bucket.take`

## 2. Benchmarks

### PERF-2.1: Make benchmarks for a hot-path feature exercise the new code, including allocations
- Flag: a new or updated benchmark whose setup never reaches the new logic (for example, only non-capturing DI probes for a capture sampler), or one that skips the rejection, admission, or cleanup paths.

### PERF-2.2: Confirm microbenchmark results with a macrobenchmark that reaches the changed path
- Flag: a claim of negligible overhead on a propagation or serialization path backed by a macrobenchmark that doesn't exercise it (for example, requests with no `tracecontext` headers).

## 3. Packaging and CI

### PERF-3.1: Lower package size limits when a change shrinks the package
- Flag: a change that reduces the SSI or OCI package size but leaves `LIB_INJECTION_IMAGE_MAX_SIZE_BYTES` or `OCI_PACKAGE_MAX_SIZE_BYTES` in `.gitlab-ci.yml` unchanged.
- Not when: the PR states the headroom is kept for a known upcoming increase.

### PERF-3.2: Pass an explicit `--jobs` to Steep in CI
- Flag: a CI `steep check` or `steep stats` command without `--jobs`; Steep limits itself to 2 workers when it detects CI.

## Don't flag
- Removing the shuffle from CI task batching when the total workflow duration is unchanged.
