# Rails 5: Demo application for Datadog APM

A generic Rails 5 web application with some common use scenarios.

For generating Datadog APM traces and profiles.

## Installation

Install [direnv](https://github.com/direnv/direnv) for applying local settings.

1. `cp .envrc.sample .envrc` and add your Datadog API key.
2. `direnv allow` to load the env var.
3. `cp docker-compose.yml.sample docker-compose.yml` and configure if necessary.
4. `docker-compose run --rm api bin/setup`

## Running the application

### To monitor performance of Docker containers with Datadog

```sh
docker run --rm --name dd-agent  -v /var/run/docker.sock:/var/run/docker.sock:ro -v /proc/:/host/proc/:ro -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro -e API_KEY=$DD_API_KEY datadog/docker-dd-agent:latest
```

### Starting the web server

Run `docker-compose up` to auto-start the webserver. It should bind to `localhost:80`.

Alternatively, you can run it manually with:

```sh
docker-compose run --rm -p 80:80 api bin/dd-demo <process>
```

The `<process>` argument is optional, and will default to `DD_DEMO_ENV_PROCESS` if not provided. See [Processes](#processes) for more details.

##### Processes

Within the container, run `bin/dd-demo <process>` where `<process>` is one of the following values:

 - `webrick`: WEBrick web server
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

You can run integration tests using the following and substituting for the Ruby major and minor version (e.g. `2.7`)

```sh
./bin/build-images -v <RUBY_VERSION>
./bin/ci -v <RUBY_VERSION>
```

Or inside a running container:

```sh
./bin/rspec
```
