# Datadog APM Ruby integration test suite

Integration tests for `datadog` that use a variety of real applications.

## Quickstart

1. Build Docker base images:

    ```bash
    ./script/build-images
    ```

You can specify which ruby version to build using the `-v` option.

2. Choose an application and follow instructions (in corresponding `README.md`.)

## Demo applications

Ruby demo applications are configured with Datadog APM, which can be used to generate sample traces/profiles. These are used to drive tests in the integration suite.

### Applications

See `README.md` in each directory for more information:

- `apps/opentelemetry`: Generates OpenTelemetry traces
- `apps/rack`: Rack application
- `apps/rails-five`: Rails 5 application
- `apps/rails-six`: Rails 6 application
- `apps/rails-seven`: Rails 7 application
- `apps/rspec`: RSpec test suite (CI)
- `apps/ruby`: Generic Ruby application
- `apps/sinatra2-classic`: Sinatra classic application
- `apps/sinatra2-modular`: Sinatra modular application

### Base images

The `images/` folders hosts some images for Ruby applications.

- `datadog/dd-apm-demo:wrk` / `images/wrk/Dockerfile`: `wrk` load testing application (for generating load)
- `datadog/dd-apm-demo:agent` / `images/agent/Dockerfile`: Datadog agent (with default configuration)
- `datadog/dd-apm-demo:rb-<RUBY_VERSION>` / `images/<RUBY_VERSION>/Dockerfile`: MRI Ruby & `Datadog::DemoEnv` (where `<RUBY_VERSION>` is minor version e.g. `2.7`)

Ruby base images include `Datadog::DemoEnv` and other helpers.

### Debugging

#### Profiling memory

Create a memory heap dump via:

```sh
# Profile for 5 minutes, dump heap to /data/app/ruby-heap.dump
# Where PID = process ID
bundle exec rbtrace -p PID -e 'Thread.new{GC.start; require "objspace"; ObjectSpace.trace_object_allocations_start; sleep(300); io=File.open("/data/app/ruby-heap.dump", "w"); ObjectSpace.dump_all(output: io); io.close}'
```

Then analyze it using `analyzer.rb` (built into the Ruby base images) with:

```sh
# Group objects by generation
ruby /vendor/dd-demo/datadog/analyzer.rb /data/app/ruby-heap.dump

# List objects in GEN_NUM, group by source location
ruby /vendor/dd-demo/datadog/analyzer.rb /data/app/ruby-heap.dump GEN_NUM

# List objects in all generations, group by source location, descending.
ruby /vendor/dd-demo/datadog/analyzer.rb /data/app/ruby-heap.dump objects

# List objects in all generations, group by source location, descending.
# Up to generation END_GEN.
ruby /vendor/dd-demo/datadog/analyzer.rb /data/app/ruby-heap.dump objects END_GEN

# List objects in all generations, group by source location, descending.
# Between generations START_GEN to END_GEN inclusive.
ruby /vendor/dd-demo/datadog/analyzer.rb /data/app/ruby-heap.dump objects END_GEN START_GEN
```
