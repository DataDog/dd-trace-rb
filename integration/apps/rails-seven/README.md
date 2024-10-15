# Rails 7: Demo application for Datadog APM

A generic Rails 7 web application with some common use scenarios.

For generating Datadog APM traces and profiles.

## Installation

Install [direnv](https://github.com/direnv/direnv) for applying local settings.

1. `cp .envrc.sample .envrc` and add your Datadog API key.
2. `direnv allow` to load the env var.
3. `docker-compose run --rm app bin/setup`

## Running the application

### To monitor performance of Docker containers with Datadog (Optional)

```sh
docker run --rm --name dd-agent  -v /var/run/docker.sock:/var/run/docker.sock:ro -v /proc/:/host/proc/:ro -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro -e API_KEY=$DD_API_KEY datadog/docker-dd-agent:latest
```

### Starting the web server

```
# Run full application + load tester
# Binds to localhost:80
docker-compose up

# OR

# Run only the application (no load tester)
# Binds to localhost:80
docker-compose run --rm -p 80:80 app "bin/run <process>"
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

#### Running the local version of `datadog`

Useful for debugging `datadog` internals or testing changes.

Update the `app` --> `environment` section in `docker-compose.yml`:

```
version: '3.4'
services:
  app:
    environment:
      # Add the following env var (path to `datadog` gem dir in the Docker container)
      - DD_DEMO_ENV_GEM_LOCAL_DATADOG=/vendor/dd-trace-rb
```

#### Running a specific version of `datadog`

Update the `app` --> `environment` section in `docker-compose.yml`:

```
version: '3.4'
services:
  app:
    environment:
      # Comment out any GEM_LOCAL env var.
      # Otherwise local source code will override your reference.
      # - DD_DEMO_ENV_GEM_LOCAL_DATADOG=/vendor/dd-trace-rb
      # Set these to the appropriate Git source and commit SHA:
      - DD_DEMO_ENV_GEM_GIT_DATADOG=https://github.com/DataDog/dd-trace-rb.git
      - DD_DEMO_ENV_GEM_REF_DATADOG=f233336994315bfa04dac581387a8152bab8b85a
```

Then delete the old containers with `docker-compose down` and start the application again.

##### Processes

Within the container, run `bin/dd-demo <process>` where `<process>` is one of the following values:

 - `puma`: Puma web server
 - `unicorn`: Unicorn web server
 - `console`: Rails console
 - `irb`: IRB session

 Alternatively, set `DD_DEMO_ENV_PROCESS` to run a particular process by default when `bin/dd-demo` is run.

##### Features

Set `DD_DEMO_ENV_FEATURES` to a comma-delimited list of any of the following values to activate the feature:

 - `tracing`: Tracing instrumentation
 - `profiling`: Profiling (NOTE: Must also set `DD_PROFILING_ENABLED` to match.)
 - `debug`: Enable diagnostic debug mode
 - `analytics`: Enable trace analytics
 - `runtime_metrics`: Enable runtime metrics
 - `pprof_to_file`: Dump profiling pprof to file instead of agent.

e.g. `DD_DEMO_ENV_FEATURES=tracing,profiling`

##### Routes

```sh
# Health check
curl -v localhost/health

# Basic test scenarios
curl -v localhost/basic/fibonacci
curl -v -XPOST localhost/basic/everything

# Job test scenarios
curl -v -XPOST localhost/jobs
```

### Load tester

Docker configuration automatically creates and runs [Wrk](https://github.com/wg/wrk) load testing containers. By default it runs the `basic/everything` scenario described in the `wrk` image to give a baseload.

You can modify the `loadtester_a` container in `docker-compose.yml` to change the load type or scenario run. Set the container's `command` to any set of arguments `wrk` accepts.

You can also define your own custom scenario by creating a LUA file, mounting it into the container, and passing it as an argument via `command`.

### Running integration tests

You can run integration tests using the following and substituting for the Ruby major and minor version (e.g. `2.7`). If you are running on ARM architecture (e.g. mac), include `DOCKER_DEFAULT_PLATFORM=linux/arm64` as a prefix for the build script and `DOCKER_BUILDKIT=0` as a prefix for the ci script.

```sh
./script/build-images -v <RUBY_VERSION>
./script/ci -v <RUBY_VERSION>
```

Or inside a running container:

```sh
./bin/rspec
```
