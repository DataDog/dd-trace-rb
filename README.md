# Datadog Trace Client

[![CircleCI](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master.svg?style=svg&circle-token=b0bd5ef866ec7f7b018f48731bb495f2d1372cc1)](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master)

``ddtrace`` is Datadog’s tracing client for Ruby. It is used to trace requests as they flow across web servers,
databases and microservices so that developers have great visiblity into bottlenecks and troublesome requests.

## Getting started

For installation instructions, check out our [setup documenation][setup docs].

For configuration instructions and details about using the API, check out our [API documentation][api docs] and [gem documentation][gem docs].

For descriptions of terminology used in APM, take a look at the [official documentation][terminology docs].

[setup docs]: https://docs.datadoghq.com/tracing/setup/ruby/
[api docs]: https://github.com/DataDog/dd-trace-rb/blob/master/docs/GettingStarted.md
[gem docs]: http://gems.datadoghq.com/trace/docs/
[terminology docs]: https://docs.datadoghq.com/tracing/terminology/

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

Available appraisals are:

* ``contrib``: default for integrations
* ``contrib-old``: default for integrations, with version suited for old Ruby (possibly unmaintained) versions
* ``rails3-mysql2``: Rails3 with Mysql
* ``rails3-postgres``: Rails 3 with Postgres
* ``rails3-postgres-redis``: Rails 3 with Postgres and Redis
* ``rails3-postgres-sidekiq``: Rails 3 with Postgres and Sidekiq
* ``rails4-mysql2``: Rails4 with Mysql
* ``rails4-postgres``: Rails 4 with Postgres
* ``rails4-postgres-redis``: Rails 4 with Postgres and Redis
* ``rails4-postgres-sidekiq``: Rails 4 with Postgres and Sidekiq
* ``rails5-mysql2``: Rails5 with Mysql
* ``rails5-postgres``: Rails 5 with Postgres
* ``rails5-postgres-redis``: Rails 5 with Postgres and Redis
* ``rails5-postgres-sidekiq``: Rails 5 with Postgres and Sidekiq

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
