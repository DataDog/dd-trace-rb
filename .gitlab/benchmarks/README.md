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
      files change.
        - `open-feature-microbenchmarks`: manual job for the OpenFeature EVP benchmark, kept
          separate since it needs a dedicated bare-metal runner.
        - Both clone the `dd-trace-rb` branch of benchmarking-platform and run
          `bp-runner ../.gitlab/benchmarks/bp-runner.microbenchmarks.yml`.
        - `microbenchmarks-check-big-regressions` fails on regressions above the threshold
          defined on `bp-runner.fail-on-regression.yml`.
- `.gitlab/benchmarks/`: files used by the microbenchmark jobs.
    - `bp-runner.microbenchmarks.yml`: runs and converts benchmark results.
    - `bp-runner.fail-on-regression.yml`: regression gate config.
- `benchmarks/`: benchmark scripts and `execution.yml` (CPU group definitions consumed by the
  `microbenchmarks` job).
- `ruby-acme-parallel-*` stages: included from
  [apm-sdks-benchmarks](https://gitlab.ddbuild.io/DataDog/apm-reliability/apm-sdks-benchmarks).
    - Change them there.

## Marking a benchmark as flaky

Add it to `FLAKY_BENCHMARKS_REGEX` in the suite's job or template:

- Macrobenchmarks: `variables` in `.macrobenchmarks` in `.gitlab/benchmarks.yml`.
- Microbenchmarks: `variables` in `microbenchmarks` in `.gitlab/benchmarks.yml`.
- OpenFeature microbenchmark: `variables` in `open-feature-microbenchmarks` in `.gitlab/benchmarks.yml`.

The benchmark still runs and reports, but doesn't fail the gate.

- The regex matches anywhere in the scenario name.
    - `only-profiling-heap` quarantines every `only-profiling-heap` scenario and metric.
    - Anchor with `^...$` to target one scenario.

```yaml
FLAKY_BENCHMARKS_REGEX: "only-profiling-heap|^high_load--only-tracing-with-tracecontext-extract--puma-utilization$"
```

Open a ticket to fix or remove it. See
[Flaky Benchmarks Monitoring](https://datadoghq.atlassian.net/wiki/spaces/APMINT/pages/7223313012/Flaky+Benchmarks+Monitoring).
