# Ruby: Demo application for Datadog APM

A generic Ruby application with some common use scenarios.

For generating Datadog APM traces and profiles.

## Installation

Install [direnv](https://github.com/direnv/direnv) for applying local settings.

1. `cp .envrc.sample .envrc` and add your Datadog API key.
2. `direnv allow` to load the env var.
3. `docker-compose run --rm app bin/setup`

## Running the application

### To monitor performance of Docker containers with Datadog

```sh
docker run --rm --name dd-agent  -v /var/run/docker.sock:/var/run/docker.sock:ro -v /proc/:/host/proc/:ro -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro -e API_KEY=$DD_API_KEY datadog/docker-dd-agent:latest
```

### Starting the application

Run `docker-compose up` to auto-start the application.

Alternatively, you can run it manually with:

```sh
docker-compose run --rm app bin/run <process>
```

The `<process>` argument is optional, and will default to `DD_DEMO_ENV_PROCESS` if not provided. See [Processes](#processes) for more details.

#### Running a specific version of Ruby

By default it runs Ruby 2.7. You must reconfigure the application env variable `RUBY_VERSION`to use a different Ruby base image.

Setting the `RUBY_VERSION` variable to 3.2 on your .envrc file would use the `datadog/dd-apm-demo:rb-3.2` image.

If you haven't yet built the base image for this version, then you must:

1. Build an appropriate Ruby base image via `./integration/script/build-images -v 3.2`

Then rebuild the application environment with:

    ```
    # Delete old containers & volumes first
    docker-compose down -v

    # Rebuild `app` image
    docker-compose build --no-cache app
    ```

Finally start the application.

##### Processes

Within the container, run `bin/run <process>` where `<process>` is one of the following values:

 - `fibonacci`: Fibonacci number generator
 - `irb`: IRB session

 Alternatively, set `DD_DEMO_ENV_PROCESS` to run a particular process by default when `bin/run` is run.

##### Features

Set `DD_DEMO_ENV_FEATURES` to a comma-delimited list of any of the following values to activate the feature:

 - `tracing`: Tracing instrumentation
 - `profiling`: Profiling (NOTE: Must also set `DD_PROFILING_ENABLED` to match.)
 - `debug`: Enable diagnostic debug mode
 - `analytics`: Enable trace analytics
 - `runtime_metrics`: Enable runtime metrics
 - `pprof_to_file`: Dump profiling pprof to file instead of agent.

e.g. `DD_DEMO_ENV_FEATURES=tracing,profiling`

### Running integration tests

You can run integration tests using the following and substituting for the Ruby major and minor version (e.g. `2.7`). Currently, this integration test has nothing to do in CI, and there are no Ruby tests in `/bin/test`.

```sh
./script/build-images -v <RUBY_VERSION>
./script/ci -v <RUBY_VERSION>
```

Or inside a running container:

```sh
./bin/test
```
