# dd-trace-rb

[![CircleCI](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master.svg?style=svg&circle-token=b0bd5ef866ec7f7b018f48731bb495f2d1372cc1)](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master)

## Documentation

You can find the latest documentation in the Datadog's [private repository][docs]

[docs]: http://gems.datadoghq.com/trace/docs/

## Getting started

### Install

If you're using ``Bundler``, just update your ``Gemfile`` as follows:

```ruby
    source 'https://rubygems.org'

    # tracing gem
    gem 'ddtrace', :source => 'http://gems.datadoghq.com/trace/'
```

### Quickstart (manual instrumentation)

If you aren't using a supported framework instrumentation, you may want to to manually instrument your code.
Adding tracing to your code is very simple. As an example, let’s imagine we have a web server and we want
to trace requests to the home page:

```ruby
    require 'ddtrace'
    require 'sinatra'
    require 'activerecord'

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

## Development

### Testing

You can launch all tests using the following rake command:

    $ rake test                     # tracer tests
    $ appraisal rake rails          # tests Rails matrix

Available appraisals are:

* ``rails-{3,4,5}-pg``: Rails with PostgreSQL
* ``rails-{3,4,5}-mysql2``: Rails with MySQL
* ``jruby-rails-{3,4}-pg``: Rails with PostgreSQL, using JRuby 9k interpreter

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
