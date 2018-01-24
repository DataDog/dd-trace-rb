# dd-trace-rb

[![CircleCI](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master.svg?style=svg&circle-token=b0bd5ef866ec7f7b018f48731bb495f2d1372cc1)](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master)

## Documentation

You can find the latest documentation on [rubydoc.info][docs]

[docs]: http://gems.datadoghq.com/trace/docs/

## Getting started

### Install

Install the Ruby client with the ``gem`` command:

    gem install ddtrace

If you're using ``Bundler``, just update your ``Gemfile`` as follows:

```ruby
    source 'https://rubygems.org'

    # tracing gem
    gem 'ddtrace'
```

To use a development/preview version, use:

```ruby
    gem 'ddtrace', :github => 'DataDog/dd-trace-rb', :branch => 'me/my-feature-branch'
```

### Quickstart (manual instrumentation)

If you aren't using a supported framework instrumentation, you may want to to manually instrument your code.
Adding tracing to your code is very simple. As an example, let’s imagine we have a web server and we want
to trace requests to the home page:

```ruby
    require 'ddtrace'
    require 'sinatra'
    require 'active_record'

    # a generic tracer that you can use across your application
    tracer = Datadog.tracer

    get '/' do
      tracer.trace('web.request') do |span|
        # set some span metadata
        span.service = 'my-web-site'
        span.resource = '/'
        span.set_tag('http.method', request.request_method)

        # trace the activerecord call
        tracer.trace('posts.fetch') do
          @posts = Posts.order(created_at: :desc).limit(10)
        end

        # trace the template rendering
        tracer.trace('template.render') do
          erb :index
        end
      end
    end
```

### Quickstart (integration)

Instead of doing the above manually, whenever an integration is available,
you can activate it. The example above would become:

```ruby
    require 'ddtrace'
    require 'sinatra'
    require 'active_record'

    Datadog.configure do |c|
      c.use :sinatra
      c.use :active_record
    end

    # now write your code naturally, it's traced automatically
    get '/' do
      @posts = Posts.order(created_at: :desc).limit(10)
      erb :index
    end
```

This will automatically trace any app inherited from `Sinatra::Application`.
To trace apps inherited from `Sinatra::Base`, you should manually register
the tracer inside your class.

```ruby
    require "ddtrace"
    require "ddtrace/contrib/sinatra/tracer"

    class App < Sinatra::Base
      register Datadog::Contrib::Sinatra::Tracer
    end
```

To know if a given framework or lib is supported by our client,
please consult our [integrations][contrib] list.

[contrib]: http://www.rubydoc.info/github/DataDog/dd-trace-rb/Datadog/Contrib

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
