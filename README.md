# Datadog Trace Client

[![CircleCI](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master.svg?style=svg&circle-token=b0bd5ef866ec7f7b018f48731bb495f2d1372cc1)](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master)

``ddtrace`` is Datadog’s tracing client for Ruby. It is used to trace requests as they flow across web servers,
databases and microservices so that developers have great visiblity into bottlenecks and troublesome requests.

## Getting started

For a basic product overview, check out our [setup documentation][setup docs].

For installation, configuration, and details about using the API, check out our [API documentation][api docs] and [gem documentation][gem docs].

For descriptions of terminology used in APM, take a look at the [official documentation][visualization docs].

[setup docs]: https://docs.datadoghq.com/tracing/setup/ruby/
[api docs]: https://github.com/DataDog/dd-trace-rb/blob/master/docs/GettingStarted.md
[gem docs]: http://gems.datadoghq.com/trace/docs/
[visualization docs]: https://docs.datadoghq.com/tracing/visualization/

## Development

### Testing

Configure your environment through:

    $ bundle install
    $ appraisal install

You can launch tests using the following Rake commands:

    $ rake test:main                                      # tracer tests
    $ appraisal rails<version>-<database> rake test:rails # tests Rails matrix
    $ appraisal contrib rake test:redis                   # tests Redis integration
    ...

Run ``rake --tasks`` for the list of available Rake tasks.
Run ``appraisal list`` for the list of available appraisals.

The test suite requires many backing services (PostgreSQL, MySQL, Redis, ...) and we're using
``docker`` and ``docker-compose`` to start these services in the CI.
To launch properly the test matrix, please [install docker][2] and [docker-compose][3] using
the instructions provided by your platform. Then launch them through:

    $ docker-compose up -d

We also enforce the Ruby [community-driven style guide][1] through Rubocop. Simply launch:

    $ rake rubocop

[1]: https://github.com/bbatsov/ruby-style-guide
[2]: https://www.docker.com/products/docker
[3]: https://www.docker.com/products/docker-compose
