# Benchmarks

GitLab CI configuration for the benchmarks that run on the
[Benchmarking Platform](https://datadoghq.atlassian.net/wiki/spaces/APMINT/pages/2419261562/Benchmarking+Platform).

## Layout

- `.gitlab/benchmarks.yml`: root config, included by `.gitlab-ci.yml`.
    - Macrobenchmarks (`.macrobenchmarks` template): k6 load tests against a GitLab instance.
        - `baseline`, `only-tracing*`, `only-profiling*` and the combined variants extend it.
        - Runs on `master`, manual elsewhere.
        - Steps live in the `ruby/gitlab` branch of
          [benchmarking-platform](https://github.com/DataDog/benchmarking-platform).
    - `ddprof-benchmark`: manual job, uses `ben-runner` from the `ruby/ddprof-benchmark` branch of
      benchmarking-platform.
    - `microbenchmarks`: runs on `master` always, on PR branches only when benchmark-relevant
      files change. Runs entirely from this repository:
      `bp-runner .gitlab/benchmarks/bp-runner.microbenchmarks.yml`.
        - `open-feature-microbenchmarks`: manual job for the OpenFeature EVP benchmark, kept
          separate since it needs a dedicated bare-metal runner.
        - `microbenchmarks-check-big-regressions` fails on regressions above the threshold
          defined on `bp-runner.fail-on-regression.yml`.
        - `microbenchmarks-pr-comment` comments the baseline-vs-candidate comparison on the PR,
          using `bp-runner.pr-comment.yml`.
- `.gitlab/benchmarks/`: everything the microbenchmark jobs need.
    - `container/`: Dockerfile (and its install scripts) for the `MICROBENCHMARKS_CI_IMAGE` CI
      image, built in-repo via the
      [`build-ci-images.template.yml`](https://github.com/DataDog/benchmarking-platform-tools/blob/main/images/templates/gitlab/build-ci-images.template.yml)
      include (see [How to rebuild the CI Docker image](#how-to-rebuild-the-ci-docker-image)).
    - `steps/`: run, analyze, upload and PR-comment scripts (copied from the former `dd-trace-rb`
      branch of [benchmarking-platform](https://github.com/DataDog/benchmarking-platform)).
    - `bp-runner.microbenchmarks.yml`: runs and converts benchmark results.
    - `bp-runner.fail-on-regression.yml`: regression gate config.
    - `bp-runner.pr-comment.yml`: PR comment config.
- `benchmarks/`: benchmark scripts and `execution.yml` (CPU group definitions consumed by the
  `microbenchmarks` job).
- `ruby-acme-parallel-*` stages: included from
  [apm-sdks-benchmarks](https://github.com/DataDog/apm-sdks-benchmarks/tree/main/.gitlab).
    - Change them there.

## How to add a new microbenchmark

1. Write the benchmark as `benchmarks/<name>.rb`, following the existing scripts. It must save
   its results as `<name>-results.json` (or `<name>-<variant>-results.json`) so the analyzer's
   `group_by_pattern` can group the repetitions.
2. Add the filename to the appropriate group in `benchmarks/execution.yml` (see the instructions
   at the top of that file). Keep `CPUS_PER_BENCHMARK * number of benchmarks` within the job's
   `CPU_AFFINITY` range, or the benchmarks queue and the job takes longer.
3. Push the branch and let the `microbenchmarks` job run. On the first run the baseline
   (master's checkout) may not contain the new benchmark, so it appears as candidate-only in the
   comparison.

## How to update an existing microbenchmark

Edit the benchmark in `benchmarks/`. Keep in mind that the baseline run executes *master's*
copy of the suite (the `how_to_fetch_release` step in `bp-runner.microbenchmarks.yml` checks
out the merge-target branch for it), so a renamed or removed benchmark still runs on the
baseline; expect a one-run mismatch on renames.

Changes that only affect CI plumbing (this directory, `.gitlab/benchmarks.yml`) don't need a
benchmark run: the benchmark jobs only auto-run when benchmark-relevant paths change, and can be
triggered manually from the pipeline otherwise.

## Marking a benchmark as flaky

Add it to `FLAKY_BENCHMARKS_REGEX` in the suite's job or template:

- Macrobenchmarks: `variables` in `.macrobenchmarks` in `.gitlab/benchmarks.yml`.
- Microbenchmarks: `variables` in `microbenchmarks` in `.gitlab/benchmarks.yml`.

The benchmark still runs and reports, but doesn't fail performance quality gates:
`microbenchmarks-check-big-regressions` (percentage-based) and the `*-check-slo-breaches` jobs of
the apm-sdks-benchmarks suites (SLO-based).

- The regex matches anywhere in the scenario name.
    - `only-profiling-heap` quarantines every `only-profiling-heap` scenario and metric.
    - Anchor with `^...$` to target one scenario.

```yaml
FLAKY_BENCHMARKS_REGEX: "only-profiling-heap|^high_load--only-tracing-with-tracecontext-extract--puma-utilization$"
```

Open a ticket to fix or remove it. See
[Flaky Benchmarks Monitoring](https://datadoghq.atlassian.net/wiki/spaces/APMINT/pages/7223313012/Flaky+Benchmarks+Monitoring).

## How to rebuild the CI Docker image

The `MICROBENCHMARKS_CI_IMAGE` used by the microbenchmark jobs is built from
`container/Dockerfile` in this directory. Rebuild and repin it whenever you change anything in
that directory (e.g. adding system packages or updating the installed benchmarking-platform
tools).

1. Edit the relevant file(s) under `.gitlab/benchmarks/container/`. Push the branch and open a
   PR.

2. The pipeline includes
   [`build-ci-images.template.yml`](https://github.com/DataDog/benchmarking-platform-tools/blob/main/images/templates/gitlab/build-ci-images.template.yml),
   which defines a manual `build-benchmark-ci-images` job that builds the image from
   `BASE_CI_IMAGE_CONTAINER_DIR` (`.gitlab/benchmarks/container`) and pushes it as
   `registry.ddbuild.io/ci/benchmarking-platform:$BASE_CI_IMAGE_SUFFIX`
   (`dd-trace-rb-<pipeline id>` — one unique tag per pipeline, so a rebuild can't shift what
   older pipelines pulled).

3. Open the pipeline on
   [gitlab.ddbuild.io/DataDog/dd-trace-rb](https://gitlab.ddbuild.io/DataDog/dd-trace-rb),
   play the `build-benchmark-ci-images` job, wait for it to finish, and copy the resulting
   image tag from its logs.

4. Repin `MICROBENCHMARKS_CI_IMAGE` in `.gitlab/benchmarks.yml` to that tag:

   ```yaml
   # Built here: <paste build-benchmark-ci-images job URL>
   MICROBENCHMARKS_CI_IMAGE: registry.ddbuild.io/ci/benchmarking-platform:dd-trace-rb-<NEW_PIPELINE_ID>
   ```

5. Push the update. The microbenchmarks now run against the rebuilt image. Verify a green
   benchmark pipeline before merging.

The `container/Dockerfile` builds on top of the `dd-trace-rb-base` image, which provides the
Ruby environment and dd-trace-rb dependencies and is built from
[`benchmarks/Dockerfile`](../../../benchmarks/Dockerfile) in this repository by the
`build-ci-images` job of the
[`dd-trace-rb` branch of benchmarking-platform](https://github.com/DataDog/benchmarking-platform/tree/dd-trace-rb).
If `benchmarks/Dockerfile` changes, that base image must be rebuilt (trigger its branch
pipeline's build job) before a new `MICROBENCHMARKS_CI_IMAGE` picks it up.

## How to run the suite locally

For quick feedback, run a single benchmark the way the job's
`how_to_run_benchmarks` step does, without the Benchmarking Platform wrapper:

```bash
bundle install
bundle exec rake compile
bundle exec ruby benchmarks/tracing_trace.rb
```

To reproduce a full CI run including the baseline comparison, run the job's steps from the
repository root inside the `MICROBENCHMARKS_CI_IMAGE` (it ships `bp-runner`) with the
environment the CI job provides (`BENCHMARKS`, `CPU_AFFINITY`, `CPUS_PER_BENCHMARK`,
`REPETITIONS`):

```bash
export ARTIFACTS_DIR="$(pwd)/artifacts"
mkdir -p "$ARTIFACTS_DIR"
BENCHMARKS="tracing_trace.rb" CPU_AFFINITY="0-23" CPUS_PER_BENCHMARK="2" REPETITIONS="5" \
  bp-runner .gitlab/benchmarks/bp-runner.microbenchmarks.yml --debug
```

`bp-runner` fetches the candidate and baseline releases and pins the benchmark CPUs, so a
faithful local run needs a comparable machine.

## Other benchmark suites (not in this directory)

- Macrobenchmarks and `ddprof-benchmark`: defined in `.gitlab/benchmarks.yml` but their steps
  still live in the `ruby/gitlab` and `ruby/ddprof-benchmark` branches of
  [benchmarking-platform](https://github.com/DataDog/benchmarking-platform).
- `ruby-acme-parallel-*` stages: steps live in
  [apm-sdks-benchmarks](https://github.com/DataDog/apm-sdks-benchmarks/tree/main/.gitlab).
