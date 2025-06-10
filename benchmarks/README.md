# `datadog` Benchmarks

## Adding a New Benchmark File

1. Use one of the following prefixes:

  - `library_` (spec in `spec/validate_benchmarks_spec.rb`)
  - `profiling_` (spec in `./spec/datadog/profiling/validate_benchmarks_spec.rb`)
  - `tracing_` (spec in `./spec/datadog/tracing/validate_benchmarks_spec.rb`)
  - `di_` (spec in `./spec/datadog/di/validate_benchmarks_spec.rb`)
  - `error_tracking` (spec in `./spec/datadog/error_tracing/validate_benchmarks_spec.rb`)

2. Add the new file to `run_all.sh` in this directory.

3. Depending on the prefix, add the new file to the correct
  `validate_benchmarks_spec.rb` as listed above

## Adding Benchmarks For a New Product

1. Create a `validate_benchmarks_spec.rb` test in the product subdirectory,
  using the existing files as a template.

2. Update this README to add the new product in the previous section.
