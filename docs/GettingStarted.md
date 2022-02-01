# Datadog Ruby Trace Client

`ddtrace` is Datadog’s tracing client for Ruby. It is used to trace requests as they flow across web servers,
databases and microservices so that developers have high visibility into bottlenecks and troublesome requests.

## Getting started

For the general APM documentation, see our [setup documentation][setup docs].

For more information about what APM looks like once your application is sending information to Datadog, take a look at [Visualizing your APM data][visualization docs].

To contribute, check out the [contribution guidelines][contribution docs] and [development guide][development docs].

[setup docs]: https://docs.datadoghq.com/tracing/
[development docs]: https://github.com/DataDog/dd-trace-rb/blob/master/README.md#development
[visualization docs]: https://docs.datadoghq.com/tracing/visualization/
[contribution docs]: https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md
[development docs]: https://github.com/DataDog/dd-trace-rb/blob/master/docs/DevelopmentGuide.md

## Table of Contents

 - [Compatibility](#compatibility)
 - [Installation](#installation)
     - [Quickstart for Rails applications](#quickstart-for-rails-applications)
     - [Quickstart for Ruby applications](#quickstart-for-ruby-applications)
     - [Quickstart for OpenTracing](#quickstart-for-opentracing)
 - [Manual instrumentation](#manual-instrumentation)
 - [Integration instrumentation](#integration-instrumentation)
     - [Action Cable](#action-cable)
     - [Action Mailer](#action-mailer)
     - [Action Pack](#action-pack)
     - [Action View](#action-view)
     - [Active Job](#active-job)
     - [Active Model Serializers](#active-model-serializers)
     - [Active Record](#active-record)
     - [Active Support](#active-support)
     - [AWS](#aws)
     - [Concurrent Ruby](#concurrent-ruby)
     - [Cucumber](#cucumber)
     - [Dalli](#dalli)
     - [DelayedJob](#delayedjob)
     - [Elasticsearch](#elasticsearch)
     - [Ethon & Typhoeus](#ethon)
     - [Excon](#excon)
     - [Faraday](#faraday)
     - [Grape](#grape)
     - [GraphQL](#graphql)
     - [gRPC](#grpc)
     - [http.rb](#httprb)
     - [httpclient](#httpclient)
     - [httpx](#httpx)
     - [Kafka](#kafka)
     - [MongoDB](#mongodb)
     - [MySQL2](#mysql2)
     - [Net/HTTP](#nethttp)
     - [Presto](#presto)
     - [Qless](#qless)
     - [Que](#que)
     - [Racecar](#racecar)
     - [Rack](#rack)
     - [Rails](#rails)
     - [Rake](#rake)
     - [Redis](#redis)
     - [Resque](#resque)
     - [Rest Client](#rest-client)
     - [RSpec](#rspec)
     - [Sequel](#sequel)
     - [Shoryuken](#shoryuken)
     - [Sidekiq](#sidekiq)
     - [Sinatra](#sinatra)
     - [Sneakers](#sneakers)
     - [Sucker Punch](#sucker-punch)
 - [Advanced configuration](#advanced-configuration)
     - [Tracer settings](#tracer-settings)
     - [Custom logging](#custom-logging)
     - [Environment and tags](#environment-and-tags)
     - [Environment variables](#environment-variables)
     - [Sampling](#sampling)
         - [Application-side sampling](#application-side-sampling)
         - [Priority sampling](#priority-sampling)
     - [Distributed tracing](#distributed-tracing)
     - [HTTP request queuing](#http-request-queuing)
     - [Processing pipeline](#processing-pipeline)
         - [Filtering](#filtering)
         - [Processing](#processing)
     - [Trace correlation](#trace-correlation)
     - [Configuring the transport layer](#configuring-the-transport-layer)
     - [Metrics](#metrics)
         - [For application runtime](#for-application-runtime)
     - [OpenTracing](#opentracing)
     - [Profiling](#profiling)
         - [Troubleshooting](#troubleshooting)
         - [Profiling Resque jobs](#profiling-resque-jobs)
 - [Known issues and suggested configurations](#known-issues-and-suggested-configurations)
    - [Payload too large](#payload-too-large)
    - [Stack level too deep](#stack-level-too-deep)

## Compatibility

**Supported Ruby interpreters**:

| Type  | Documentation              | Version | Support type                         | Gem version support |
| ----- | -------------------------- | -----   | ------------------------------------ | ------------------- |
| MRI   | https://www.ruby-lang.org/ | 3.0     | Full                                 | Latest              |
|       |                            | 2.7     | Full                                 | Latest              |
|       |                            | 2.6     | Full                                 | Latest              |
|       |                            | 2.5     | Full                                 | Latest              |
|       |                            | 2.4     | Full                                 | Latest              |
|       |                            | 2.3     | Full                                 | Latest              |
|       |                            | 2.2     | Full                                 | Latest              |
|       |                            | 2.1     | Full                                 | Latest              |
|       |                            | 2.0     | EOL since June 7th, 2021             | < 0.50.0            |
|       |                            | 1.9.3   | EOL since August 6th, 2020           | < 0.27.0            |
|       |                            | 1.9.1   | EOL since August 6th, 2020           | < 0.27.0            |
| JRuby | https://www.jruby.org      | 9.2     | Full                                 | Latest              |

**Supported web servers**:

| Type      | Documentation                     | Version      | Support type |
| --------- | --------------------------------- | ------------ | ------------ |
| Puma      | http://puma.io/                   | 2.16+ / 3.6+ | Full         |
| Unicorn   | https://bogomips.org/unicorn/     | 4.8+ / 5.1+  | Full         |
| Passenger | https://www.phusionpassenger.com/ | 5.0+         | Full         |

**Supported tracing frameworks**:

| Type        | Documentation                                   | Version               | Gem version support |
| ----------- | ----------------------------------------------- | --------------------- | ------------------- |
| OpenTracing | https://github.com/opentracing/opentracing-ruby | 0.4.1+ (w/ Ruby 2.1+) | >= 0.16.0           |

*Full* support indicates all tracer features are available.

*Deprecated* indicates support will transition to *Maintenance* in a future release.

*Maintenance* indicates only critical bugfixes are backported until EOL.

*EOL* indicates support is no longer provided.

### Apple macOS support

Use of `ddtrace` on macOS is supported for development, but not for production deployments.

### Microsoft Windows support

Using `ddtrace` on Microsoft Windows is currently unsupported. We'll still accept community contributions and issues,
but will consider them as having low priority.

## Installation

The following steps will help you quickly start tracing your Ruby application.

### Configure the Datadog Agent for APM

Before downloading tracing on your application, [install the Datadog Agent on the host](https://docs.datadoghq.com/agent/). The Ruby APM tracer sends trace data through the Datadog Agent.

Install and configure the Datadog Agent to receive traces from your now instrumented application. By default the Datadog Agent is enabled in your `datadog.yaml` file under `apm_enabled: true` and listens for trace traffic at `localhost:8126`. For containerized environments, follow the steps below to enable trace collection within the Datadog Agent.

#### Containers

1. Set `apm_non_local_traffic: true` in your main [`datadog.yaml` configuration file](https://docs.datadoghq.com/agent/guide/agent-configuration-files/#agent-main-configuration-file).

2. See the specific setup instructions for [Docker](https://docs.datadoghq.com/agent/docker/apm/?tab=ruby), [Kubernetes](https://docs.datadoghq.com/agent/kubernetes/apm/?tab=helm), [Amazon ECS](https://docs.datadoghq.com/agent/amazon_ecs/apm/?tab=ruby) or [Fargate](https://docs.datadoghq.com/integrations/ecs_fargate/#trace-collection) to ensure that the Agent is configured to receive traces in a containerized environment:

3. After having instrumented your application, the tracing client sends traces to `localhost:8126` by default.  If this is not the correct host and port change it by setting the env variables `DD_AGENT_HOST` and `DD_TRACE_AGENT_PORT`.


### Quickstart for Rails applications

#### Automatic instrumentation

1. Add the `ddtrace` gem to your Gemfile:

    ```ruby
    source 'https://rubygems.org'
    gem 'ddtrace', require: 'ddtrace/auto_instrument'
    ```

2. Install the gem with `bundle install`

3. You can configure, override, or disable any specific integration settings by also adding a Rails manual instrumentation configuration file (next).

#### Manual instrumentation

1. Add the `ddtrace` gem to your Gemfile:

    ```ruby
    source 'https://rubygems.org'
    gem 'ddtrace'
    ```

2. Install the gem with `bundle install`
3. Create a `config/initializers/datadog.rb` file containing:

    ```ruby
    Datadog::Tracing.configure do |c|
      # This will activate auto-instrumentation for Rails
      c.instrument :rails
    end
    ```

    You can also activate additional integrations here (see [Integration instrumentation](#integration-instrumentation))

### Quickstart for Ruby applications

#### Automatic instrumentation

1. Install the gem with `gem install ddtrace`
2. Requiring any [supported libraries or frameworks](#integration-instrumentation) that should be instrumented.
3. Add `require 'ddtrace/auto_instrument'` to your application. _Note:_ This must be done _after_ requiring any supported libraries or frameworks.

    ```ruby
    # Example frameworks and libraries
    require 'sinatra'
    require 'faraday'
    require 'redis'

    require 'ddtrace/auto_instrument'
    ```

    You can configure, override, or disable any specific integration settings by also adding a Ruby manual configuration block (next).

#### Manual instrumentation

1. Install the gem with `gem install ddtrace`
2. Add a configuration block to your Ruby application:

    ```ruby
    require 'ddtrace'
    Datadog::Tracing.configure do |c|
      # Configure the tracer here.
      # Activate integrations, change tracer settings, etc...
      # By default without additional configuration, nothing will be traced.
    end
    ```

3. Add or activate instrumentation by doing either of the following:
    - Activate integration instrumentation (see [Integration instrumentation](#integration-instrumentation))
    - Add manual instrumentation around your code (see [Manual instrumentation](#manual-instrumentation))

### Quickstart for OpenTracing

1. Install the gem with `gem install ddtrace`
2. To your OpenTracing configuration file, add the following:

    ```ruby
    require 'opentracing'
    require 'datadog/tracing'
    require 'datadog/opentracer'

    # Activate the Datadog tracer for OpenTracing
    OpenTracing.global_tracer = Datadog::OpenTracer::Tracer.new
    ```

3. (Optional) Add a configuration block to your Ruby application to configure Datadog with:

    ```ruby
    Datadog::Tracing.configure do |c|
      # Configure the Datadog tracer here.
      # Activate integrations, change tracer settings, etc...
      # By default without additional configuration,
      # no additional integrations will be traced, only
      # what you have instrumented with OpenTracing.
    end
    ```

4. (Optional) Add or activate additional instrumentation by doing either of the following:
    - Activate Datadog integration instrumentation (see [Integration instrumentation](#integration-instrumentation))
    - Add Datadog manual instrumentation around your code (see [Manual instrumentation](#manual-instrumentation))

### Final steps for installation

After setting up, your services will appear on the [APM services page](https://app.datadoghq.com/apm/services) within a few minutes. Learn more about [using the APM UI][visualization docs].

## Manual Instrumentation

If you aren't using a supported framework instrumentation, you may want to manually instrument your code.

To trace any Ruby code, you can use the `Datadog::Tracing.trace` method:

```ruby
Datadog::Tracing.trace(name, options) do |span, trace|
  # Wrap this block around the code you want to instrument
  # Additionally, you can modify the span here.
  # e.g. Change the resource name, set tags, etc...
end
```

Where `name` should be a `String` that describes the generic kind of operation being done (e.g. `'web.request'`, or `'request.parse'`)

And `options` is an optional `Hash` that accepts the following parameters:

| Key | Type | Description | Default |
| --------------- | ----------------------- | --- | --- |
| `autostart`     | `Bool`                  | Whether the time measurement should be started automatically. If `false`, user must call `span.start`. | `true` |
| `continue_from` | `Datadog::TraceDigest`  | Continues a trace that originated from another execution context. TraceDigest describes the continuation point. | `nil` |
| `on_error`      | `Proc`                  | Overrides error handling behavior, when a span raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. | `proc { |span, error| span.set_error(error) unless span.nil? }` |
| `resource`      | `String`                | Name of the resource or action being operated on. Traces with the same resource value will be grouped together for the purpose of metrics (but still independently viewable.) Usually domain specific, such as a URL, query, request, etc. (e.g. `'Article#submit'`, `http://example.com/articles/list`.) | `name` of Span. |
| `service`       | `String`                | The service name which this span belongs (e.g. `'my-web-service'`) | Tracer `default-service`, `$PROGRAM_NAME` or `'ruby'` |
| `start_time`    | `Time`                  | When the span actually starts. Useful when tracing events that have already happened. | `Time.now` |
| `tags`          | `Hash`                  | Extra tags which should be added to the span. | `{}` |
| `type`          | `String`                | The type of the span (such as `'http'`, `'db'`, etc.) | `nil` |

It's highly recommended you set both `service` and `resource` at a minimum. Spans without a `service` or `resource` as `nil` will be discarded by the Datadog agent.

Example of manual instrumentation in action:

```ruby
get '/posts' do
  Datadog::Tracing.trace('web.request', service: 'my-blog', resource: 'GET /posts') do |span|
    # Trace the activerecord call
    Datadog::Tracing.trace('posts.fetch') do
      @posts = Posts.order(created_at: :desc).limit(10)
    end

    # Add some APM tags
    span.set_tag('http.method', request.request_method)
    span.set_tag('posts.count', @posts.length)

    # Trace the template rendering
    Datadog::Tracing.trace('template.render') do
      erb :index
    end
  end
end
```

### Asynchronous tracing

It might not always be possible to wrap `Datadog::Tracing.trace` around a block of code. Some event or notification based instrumentation might only notify you when an event begins or ends.

To trace these operations, you can trace code asynchronously by calling `Datadog::Tracing.trace` without a block:

```ruby
# Some instrumentation framework calls this after an event finishes...
def db_query(start, finish, query)
  span = Datadog::Tracing.trace('database.query', start_time: start)
  span.resource = query
  span.finish(finish)
end
```

Calling `Datadog::Tracing.trace` without a block will cause the function to return a `Datadog::SpanOperation` that is started, but not finished. You can then modify this span however you wish, then close it `finish`.

*You must not leave any unfinished spans.* If any spans are left open when the trace completes, the trace will be discarded. You can [activate debug mode](#tracer-settings) to check for warnings if you suspect this might be happening.

To avoid this scenario when handling start/finish events, you can use `Datadog::Tracing.active_span` to get the current active span.

```ruby
# e.g. ActiveSupport::Notifications calls this when an event starts
def start(name, id, payload)
  # Start a span
  Datadog::Tracing.trace(name)
end

# e.g. ActiveSupport::Notifications calls this when an event finishes
def finish(name, id, payload)
  # Retrieve current active span (thread-safe)
  current_span = Datadog::Tracing.active_span
  unless current_span.nil?
    current_span.resource = payload[:query]
    current_span.finish
  end
end
```
### Enriching traces from nested methods

You can tag additional information to the current active span from any method. Note however that if the method is called and there is no span currently active `active_span` will be nil.

```ruby
# e.g. adding tag to active span

current_span = Datadog::Tracing.active_span
current_span.set_tag('my_tag', 'my_value') unless current_span.nil?
```

You can also get the current active trace using the `active_trace` method. This method will return `nil` if there is no active trace.

```ruby
# e.g. accessing active trace

current_trace = Datadog::Tracing.active_trace
```

## Integration instrumentation

Many popular libraries and frameworks are supported out-of-the-box, which can be auto-instrumented. Although they are not activated automatically, they can be easily activated and configured by using the `Datadog::Tracing.configure` API:

```ruby
Datadog::Tracing.configure do |c|
  # Activates and configures an integration
  c.instrument :integration_name, options
end
```

`options` is a `Hash` of integration-specific configuration settings.

For a list of available integrations, and their configuration options, please refer to the following:

| Name                       | Key                        | Versions Supported: MRI  | Versions Supported: JRuby | How to configure                    | Gem source                                                                     |
| -------------------------- | -------------------------- | ------------------------ | --------------------------| ----------------------------------- | ------------------------------------------------------------------------------ |
| Action Cable               | `action_cable`             | `>= 5.0`                 | `>= 5.0`                  | *[Link](#action-cable)*             | *[Link](https://github.com/rails/rails/tree/master/actioncable)*               |
| Action Mailer              | `action_mailer`            | `>= 5.0`                 | `>= 5.0`                  | *[Link](#action-mailer)*            | *[Link](https://github.com/rails/rails/tree/master/actionmailer)*              |
| Action Pack                | `action_pack`              | `>= 3.2`                 | `>= 3.2`                  | *[Link](#action-pack)*              | *[Link](https://github.com/rails/rails/tree/master/actionpack)*                |
| Action View                | `action_view`              | `>= 3.2`                 | `>= 3.2`                  | *[Link](#action-view)*              | *[Link](https://github.com/rails/rails/tree/master/actionview)*                |
| Active Job                 | `active_job`               | `>= 4.2`                 | `>= 4.2`                  | *[Link](#active-job)*               | *[Link](https://github.com/rails/rails/tree/master/activejob)*             |
| Active Model Serializers   | `active_model_serializers` | `>= 0.9`                 | `>= 0.9`                  | *[Link](#active-model-serializers)* | *[Link](https://github.com/rails-api/active_model_serializers)*                |
| Active Record              | `active_record`            | `>= 3.2`                 | `>= 3.2`                  | *[Link](#active-record)*            | *[Link](https://github.com/rails/rails/tree/master/activerecord)*              |
| Active Support             | `active_support`           | `>= 3.2`                 | `>= 3.2`                  | *[Link](#active-support)*           | *[Link](https://github.com/rails/rails/tree/master/activesupport)*             |
| AWS                        | `aws`                      | `>= 2.0`                 | `>= 2.0`                  | *[Link](#aws)*                      | *[Link](https://github.com/aws/aws-sdk-ruby)*                                  |
| Concurrent Ruby            | `concurrent_ruby`          | `>= 0.9`                 | `>= 0.9`                  | *[Link](#concurrent-ruby)*          | *[Link](https://github.com/ruby-concurrency/concurrent-ruby)*                  |
| Cucumber                   | `cucumber`                 | `>= 3.0`                 | `>= 1.7.16`               | *[Link](#cucumber)*                 | *[Link](https://github.com/cucumber/cucumber-ruby)*                            |
| Dalli                      | `dalli`                    | `>= 2.0`                 | `>= 2.0`                  | *[Link](#dalli)*                    | *[Link](https://github.com/petergoldstein/dalli)*                              |
| DelayedJob                 | `delayed_job`              | `>= 4.1`                 | `>= 4.1`                  | *[Link](#delayedjob)*               | *[Link](https://github.com/collectiveidea/delayed_job)*                        |
| Elasticsearch              | `elasticsearch`            | `>= 1.0`                 | `>= 1.0`                  | *[Link](#elasticsearch)*            | *[Link](https://github.com/elastic/elasticsearch-ruby)*                        |
| Ethon                      | `ethon`                    | `>= 0.11`                | `>= 0.11`                 | *[Link](#ethon)*                    | *[Link](https://github.com/typhoeus/ethon)*                                    |
| Excon                      | `excon`                    | `>= 0.50`                | `>= 0.50`                 | *[Link](#excon)*                    | *[Link](https://github.com/excon/excon)*                                       |
| Faraday                    | `faraday`                  | `>= 0.14`                | `>= 0.14`                 | *[Link](#faraday)*                  | *[Link](https://github.com/lostisland/faraday)*                                |
| Grape                      | `grape`                    | `>= 1.0`                 | `>= 1.0`                  | *[Link](#grape)*                    | *[Link](https://github.com/ruby-grape/grape)*                                  |
| GraphQL                    | `graphql`                  | `>= 1.7.9`               | `>= 1.7.9`                | *[Link](#graphql)*                  | *[Link](https://github.com/rmosolgo/graphql-ruby)*                             |
| gRPC                       | `grpc`                     | `>= 1.7`                 | *gem not available*       | *[Link](#grpc)*                     | *[Link](https://github.com/grpc/grpc/tree/master/src/rubyc)*                   |
| http.rb                    | `httprb`                   | `>= 2.0`                 | `>= 2.0`                  | *[Link](#httprb)*                   | *[Link](https://github.com/httprb/http)*                                       |
| httpclient                 | `httpclient`               | `>= 2.2`                 | `>= 2.2`                  | *[Link](#httpclient)*               | *[Link](https://github.com/nahi/httpclient)*                                     |
| httpx                      | `httpx`                    | `>= 0.11`                | `>= 0.11`                 | *[Link](#httpx)*                    | *[Link](https://gitlab.com/honeyryderchuck/httpx)*                             |
| Kafka                      | `ruby-kafka`               | `>= 0.7.10`              | `>= 0.7.10`               | *[Link](#kafka)*                    | *[Link](https://github.com/zendesk/ruby-kafka)*                                |
| Makara (via Active Record) | `makara`                   | `>= 0.3.5`               | `>= 0.3.5`                | *[Link](#active-record)*            | *[Link](https://github.com/instacart/makara)*                                  |
| MongoDB                    | `mongo`                    | `>= 2.1`                 | `>= 2.1`                  | *[Link](#mongodb)*                  | *[Link](https://github.com/mongodb/mongo-ruby-driver)*                         |
| MySQL2                     | `mysql2`                   | `>= 0.3.21`              | *gem not available*       | *[Link](#mysql2)*                   | *[Link](https://github.com/brianmario/mysql2)*                                 |
| Net/HTTP                   | `http`                     | *(Any supported Ruby)*   | *(Any supported Ruby)*    | *[Link](#nethttp)*                  | *[Link](https://ruby-doc.org/stdlib-2.4.0/libdoc/net/http/rdoc/Net/HTTP.html)* |
| Presto                     | `presto`                   | `>= 0.5.14`              | `>= 0.5.14`               | *[Link](#presto)*                   | *[Link](https://github.com/treasure-data/presto-client-ruby)*                  |
| Qless                      | `qless`                    | `>= 0.10.0`              | `>= 0.10.0`               | *[Link](#qless)*                    | *[Link](https://github.com/seomoz/qless)*                                      |
| Que                        | `que`                      | `>= 1.0.0.beta2`         | `>= 1.0.0.beta2`          | *[Link](#que)*                      | *[Link](https://github.com/que-rb/que)*                                        |
| Racecar                    | `racecar`                  | `>= 0.3.5`               | `>= 0.3.5`                | *[Link](#racecar)*                  | *[Link](https://github.com/zendesk/racecar)*                                   |
| Rack                       | `rack`                     | `>= 1.1`                 | `>= 1.1`                  | *[Link](#rack)*                     | *[Link](https://github.com/rack/rack)*                                         |
| Rails                      | `rails`                    | `>= 3.2`                 | `>= 3.2`                  | *[Link](#rails)*                    | *[Link](https://github.com/rails/rails)*                                       |
| Rake                       | `rake`                     | `>= 12.0`                | `>= 12.0`                 | *[Link](#rake)*                     | *[Link](https://github.com/ruby/rake)*                                         |
| Redis                      | `redis`                    | `>= 3.2`                 | `>= 3.2`                  | *[Link](#redis)*                    | *[Link](https://github.com/redis/redis-rb)*                                    |
| Resque                     | `resque`                   | `>= 1.0`                 | `>= 1.0`                  | *[Link](#resque)*                   | *[Link](https://github.com/resque/resque)*                                     |
| Rest Client                | `rest-client`              | `>= 1.8`                 | `>= 1.8`                  | *[Link](#rest-client)*              | *[Link](https://github.com/rest-client/rest-client)*                           |
| RSpec                      | `rspec`.                   | `>= 3.0.0`               | `>= 3.0.0`                | *[Link](#rspec)*.                   | *[Link](https://github.com/rspec/rspec)*                                       |
| Sequel                     | `sequel`                   | `>= 3.41`                | `>= 3.41`                 | *[Link](#sequel)*                   | *[Link](https://github.com/jeremyevans/sequel)*                                |
| Shoryuken                  | `shoryuken`                | `>= 3.2`                 | `>= 3.2`                  | *[Link](#shoryuken)*                | *[Link](https://github.com/phstc/shoryuken)*                                   |
| Sidekiq                    | `sidekiq`                  | `>= 3.5.4`               | `>= 3.5.4`                | *[Link](#sidekiq)*                  | *[Link](https://github.com/mperham/sidekiq)*                                   |
| Sinatra                    | `sinatra`                  | `>= 1.4`                 | `>= 1.4`                  | *[Link](#sinatra)*                  | *[Link](https://github.com/sinatra/sinatra)*                                   |
| Sneakers                   | `sneakers`                 | `>= 2.12.0`              | `>= 2.12.0`               | *[Link](#sneakers)*                 | *[Link](https://github.com/jondot/sneakers)*                                   |
| Sucker Punch               | `sucker_punch`             | `>= 2.0`                 | `>= 2.0`                  | *[Link](#sucker-punch)*             | *[Link](https://github.com/brandonhilkert/sucker_punch)*                       |

### Action Cable

The Action Cable integration traces broadcast messages and channel actions.

You can enable it through `Datadog::Tracing.configure`:

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :action_cable
end
```

### Action Mailer

The Action Mailer integration provides tracing for Rails 5 ActionMailer actions.

You can enable it through `Datadog::Tracing.configure`:

```ruby
require 'ddtrace'
 Datadog::Tracing.configure do |c|
  c.instrument :action_mailer, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `analytics_enabled` | Enable analytics for spans produced by this integration. `true` for on, `nil` to defer to global setting, `false` for off. | `false` |
| `email_data` | Whether or not to append additional email payload metadata to `action_mailer.deliver` spans. Fields include `['subject', 'to', 'from', 'bcc', 'cc', 'date', 'perform_deliveries']`. | `false` |

### Action Pack

Most of the time, Action Pack is set up as part of Rails, but it can be activated separately:

```ruby
require 'actionpack'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :action_pack
end
```

### Action View

Most of the time, Action View is set up as part of Rails, but it can be activated separately:

```ruby
require 'actionview'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :action_view, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| ---| --- | --- |
| `template_base_path` | Used when the template name is parsed. If you don't store your templates in the `views/` folder, you may need to change this value | `'views/'` |

### Active Job

Most of the time, Active Job is set up as part of Rails, but it can be activated separately:

```ruby
require 'active_job'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :active_job
end

ExampleJob.perform_later
```

### Active Model Serializers

The Active Model Serializers integration traces the `serialize` event for version 0.9+ and the `render` event for version 0.10+.

```ruby
require 'active_model_serializers'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :active_model_serializers
end

my_object = MyModel.new(name: 'my object')
ActiveModelSerializers::SerializableResource.new(test_obj).serializable_hash
```

### Active Record

Most of the time, Active Record is set up as part of a web framework (Rails, Sinatra...) however, it can be set up alone:

```ruby
require 'tmpdir'
require 'sqlite3'
require 'active_record'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :active_record, options
end

Dir::Tmpname.create(['test', '.sqlite']) do |db|
  conn = ActiveRecord::Base.establish_connection(adapter: 'sqlite3',
                                                 database: db)
  conn.connection.execute('SELECT 42') # traced!
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| ---| --- | --- |
| `service_name` | Service name used for database portion of `active_record` instrumentation. | Name of database adapter (e.g. `'mysql2'`) |

**Configuring trace settings per database**

You can configure trace settings per database connection by using the `describes` option:

```ruby
# Provide a `:describes` option with a connection key.
# Any of the following keys are acceptable and equivalent to one another.
# If a block is provided, it yields a Settings object that
# accepts any of the configuration options listed above.

Datadog::Tracing.configure do |c|
  # Symbol matching your database connection in config/database.yml
  # Only available if you are using Rails with ActiveRecord.
  c.instrument :active_record, describes: :secondary_database, service_name: 'secondary-db'

  # Block configuration pattern.
  c.instrument :active_record, describes: :secondary_database do |second_db|
    second_db.service_name = 'secondary-db'
  end

  # Connection string with the following connection settings:
  # adapter, username, host, port, database
  # Other fields are ignored.
  c.instrument :active_record, describes: 'mysql2://root@127.0.0.1:3306/mysql', service_name: 'secondary-db'

  # Hash with following connection settings:
  # adapter, username, host, port, database
  # Other fields are ignored.
  c.instrument :active_record, describes: {
      adapter:  'mysql2',
      host:     '127.0.0.1',
      port:     '3306',
      database: 'mysql',
      username: 'root'
    },
    service_name: 'secondary-db'

  # If using the `makara` gem, it's possible to match on connection `role`:
  c.instrument :active_record, describes: { makara_role: 'primary' }, service_name: 'primary-db'
  c.instrument :active_record, describes: { makara_role: 'replica' }, service_name: 'secondary-db'
end
```

You can also create configurations based on partial matching of database connection fields:

```ruby
Datadog::Tracing.configure do |c|
  # Matches any connection on host `127.0.0.1`.
  c.instrument :active_record, describes: { host:  '127.0.0.1' }, service_name: 'local-db'

  # Matches any `mysql2` connection.
  c.instrument :active_record, describes: { adapter: 'mysql2'}, service_name: 'mysql-db'

  # Matches any `mysql2` connection to the `reports` database.
  #
  # In case of multiple matching `describe` configurations, the latest one applies.
  # In this case a connection with both adapter `mysql` and database `reports`
  # will be configured `service_name: 'reports-db'`, not `service_name: 'mysql-db'`.
  c.instrument :active_record, describes: { adapter: 'mysql2', database:  'reports'}, service_name: 'reports-db'
end
```

When multiple `describes` configurations match a connection, the latest configured rule that matches will be applied.

If ActiveRecord traces an event that uses a connection that matches a key defined by `describes`, it will use the trace settings assigned to that connection. If the connection does not match any of the described connections, it will use default settings defined by `c.instrument :active_record` instead.

### Active Support

Most of the time, Active Support is set up as part of Rails, but it can be activated separately:

```ruby
require 'activesupport'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :active_support, options
end

cache = ActiveSupport::Cache::MemoryStore.new
cache.read('city')
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| ---| --- | --- |
| `cache_service` | Service name used for caching with `active_support` instrumentation. | `active_support-cache` |

### AWS

The AWS integration will trace every interaction (e.g. API calls) with AWS services (S3, ElastiCache etc.).

```ruby
require 'aws-sdk'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :aws, options
end

# Perform traced call
Aws::S3::Client.new.list_buckets
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `aws` instrumentation | `'aws'` |

### Concurrent Ruby

The Concurrent Ruby integration adds support for context propagation when using `::Concurrent::Future`.
Making sure that code traced within the `Future#execute` will have correct parent set.

To activate your integration, use the `Datadog::Tracing.configure` method:

```ruby
# Inside Rails initializer or equivalent
Datadog::Tracing.configure do |c|
  # Patches ::Concurrent::Future to use ExecutorService that propagates context
  c.instrument :concurrent_ruby
end

# Pass context into code executed within Concurrent::Future
Datadog::Tracing.trace('outer') do
  Concurrent::Future.execute { Datadog::Tracing.trace('inner') { } }.wait
end
```

### Cucumber

Cucumber integration will trace all executions of scenarios and steps when using `cucumber` framework.

To activate your integration, use the `Datadog::Tracing.configure` method:

```ruby
require 'cucumber'
require 'ddtrace'

# Configure default Cucumber integration
Datadog::Tracing.configure do |c|
  c.instrument :cucumber, options
end

# Example of how to attach tags from scenario to active span
Around do |scenario, block|
  active_span = Datadog::Tracing.configuration[:cucumber][:tracer].active_span
  unless active_span.nil?
    scenario.tags.filter { |tag| tag.include? ':' }.each do |tag|
      active_span.set_tag(*tag.name.split(':', 2))
    end
  end
  block.call
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Cucumber tests should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `service_name` | Service name used for `cucumber` instrumentation. | `'cucumber'` |
| `operation_name` | Operation name used for `cucumber` instrumentation. Useful if you want rename automatic trace metrics e.g. `trace.#{operation_name}.errors`. | `'cucumber.test'` |

### Dalli

Dalli integration will trace all calls to your `memcached` server:

```ruby
require 'dalli'
require 'ddtrace'

# Configure default Dalli tracing behavior
Datadog::Tracing.configure do |c|
  c.instrument :dalli, options
end

# Configure Dalli tracing behavior for single client
client = Dalli::Client.new('localhost:11211', options)
client.set('abc', 123)
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `dalli` instrumentation | `'memcached'` |

### DelayedJob

The DelayedJob integration uses lifecycle hooks to trace the job executions and enqueues.

You can enable it through `Datadog::Tracing.configure`:

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :delayed_job, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Elasticsearch

The Elasticsearch integration will trace any call to `perform_request` in the `Client` object:

```ruby
require 'elasticsearch/transport'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :elasticsearch, options
end

# Perform a query to Elasticsearch
client = Elasticsearch::Client.new url: 'http://127.0.0.1:9200'
response = client.perform_request 'GET', '_cluster/health'
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `quantize` | Hash containing options for quantization. May include `:show` with an Array of keys to not quantize (or `:all` to skip quantization), or `:exclude` with Array of keys to exclude entirely. | `{}` |
| `service_name` | Service name used for `elasticsearch` instrumentation | `'elasticsearch'` |

### Ethon

The `ethon` integration will trace any HTTP request through `Easy` or `Multi` objects. Note that this integration also supports `Typhoeus` library which is based on `Ethon`.

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :ethon, options

  # optionally, specify a different service name for hostnames matching a regex
  c.instrument :ethon, describes: /user-[^.]+\.example\.com/ do |ethon|
    ethon.service_name = 'user.example.com'
    ethon.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `service_name` | Service name for `ethon` instrumentation. | `'ethon'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |

### Excon

The `excon` integration is available through the `ddtrace` middleware:

```ruby
require 'excon'
require 'ddtrace'

# Configure default Excon tracing behavior
Datadog::Tracing.configure do |c|
  c.instrument :excon, options

  # optionally, specify a different service name for hostnames matching a regex
  c.instrument :excon, describes: /user-[^.]+\.example\.com/ do |excon|
    excon.service_name = 'user.example.com'
    excon.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end

connection = Excon.new('https://example.com')
connection.get
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `error_handler` | A `Proc` that accepts a `response` parameter. If it evaluates to a *truthy* value, the trace span is marked as an error. By default only sets 5XX responses as errors. | `nil` |
| `service_name` | Service name for Excon instrumentation. When provided to middleware for a specific connection, it applies only to that connection object. | `'excon'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |

**Configuring connections to use different settings**

If you use multiple connections with Excon, you can give each of them different settings by configuring their constructors with middleware:

```ruby
# Wrap the Datadog tracing middleware around the default middleware stack
Excon.new(
  'http://example.com',
  middlewares: Datadog::Tracing::Contrib::Excon::Middleware.with(options).around_default_stack
)

# Insert the middleware into a custom middleware stack.
# NOTE: Trace middleware must be inserted after ResponseParser!
Excon.new(
  'http://example.com',
  middlewares: [
    Excon::Middleware::ResponseParser,
    Datadog::Tracing::Contrib::Excon::Middleware.with(options),
    Excon::Middleware::Idempotent
  ]
)
```

Where `options` is a Hash that contains any of the parameters listed in the table above.

### Faraday

The `faraday` integration is available through the `ddtrace` middleware:

```ruby
require 'faraday'
require 'ddtrace'

# Configure default Faraday tracing behavior
Datadog::Tracing.configure do |c|
  c.instrument :faraday, options

  # optionally, specify a different service name for hostnames matching a regex
  c.instrument :faraday, describes: /user-[^.]+\.example\.com/ do |faraday|
    faraday.service_name = 'user.example.com'
    faraday.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end

# In case you want to override the global configuration for a certain client instance
connection = Faraday.new('https://example.com') do |builder|
  builder.use(:ddtrace, options)
  builder.adapter Faraday.default_adapter
end

connection.get('/foo')
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `error_handler` | A `Proc` that accepts a `response` parameter. If it evaluates to a *truthy* value, the trace span is marked as an error. By default only sets 5XX responses as errors. | `nil` |
| `service_name` | Service name for Faraday instrumentation. When provided to middleware for a specific connection, it applies only to that connection object. | `'faraday'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |

### Grape

The Grape integration adds the instrumentation to Grape endpoints and filters. This integration can work side by side with other integrations like Rack and Rails.

To activate your integration, use the `Datadog::Tracing.configure` method before defining your Grape application:

```ruby
# api.rb
require 'grape'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :grape, options
end

# Then define your application
class RackTestingAPI < Grape::API
  desc 'main endpoint'
  get :success do
    'Hello world!'
  end
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Grape should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `error_statuses`| Defines a status code or range of status codes which should be marked as errors. `'404,405,500-599'` or `[404,405,'500-599']` | `nil` |

### GraphQL

The GraphQL integration activates instrumentation for GraphQL queries.

To activate your integration, use the `Datadog::Tracing.configure` method:

```ruby
# Inside Rails initializer or equivalent
Datadog::Tracing.configure do |c|
  c.instrument :graphql, schemas: [YourSchema], options
end

# Then run a GraphQL query
YourSchema.execute(query, variables: {}, context: {}, operation_name: nil)
```

The `use :graphql` method accepts the following parameters. Additional options can be substituted in for `options`:

| Key | Description | Default |
| --- | ----------- | ------- |
| `schemas` | Required. Array of `GraphQL::Schema` objects which to trace. Tracing will be added to all the schemas listed, using the options provided to this configuration. If you do not provide any, then tracing will not be activated. | `[]` |

**Manually configuring GraphQL schemas**

If you prefer to individually configure the tracer settings for a schema (e.g. you have multiple schemas with different service names), in the schema definition, you can add the following [using the GraphQL API](http://graphql-ruby.org/queries/tracing.html):

```ruby
# Class-based schema
class YourSchema < GraphQL::Schema
  use(
    GraphQL::Tracing::DataDogTracing,
    service: 'graphql'
  )
end
```

```ruby
# .define-style schema
YourSchema = GraphQL::Schema.define do
  use(
    GraphQL::Tracing::DataDogTracing,
    service: 'graphql'
  )
end
```

Or you can modify an already defined schema:

```ruby
# Class-based schema
YourSchema.use(
    GraphQL::Tracing::DataDogTracing,
    service: 'graphql'
)
```

```ruby
# .define-style schema
YourSchema.define do
  use(
    GraphQL::Tracing::DataDogTracing,
    service: 'graphql'
  )
end
```

Do *NOT* `use :graphql` in `Datadog::Tracing.configure` if you choose to configure manually, as to avoid double tracing. These two means of configuring GraphQL tracing are considered mutually exclusive.

### gRPC

The `grpc` integration adds both client and server interceptors, which run as middleware before executing the service's remote procedure call. As gRPC applications are often distributed, the integration shares trace information between client and server.

To setup your integration, use the `Datadog::Tracing.configure` method like so:

```ruby
require 'grpc'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :grpc, options
end

# Server side
server = GRPC::RpcServer.new
server.add_http2_port('localhost:50051', :this_port_is_insecure)
server.handle(Demo)
server.run_till_terminated

# Client side
client = Demo.rpc_stub_class.new('localhost:50051', :this_channel_is_insecure)
client.my_endpoint(DemoMessage.new(contents: 'hello!'))
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `grpc` instrumentation | `'grpc'` |
| `error_handler` | Custom error handler invoked when a request is an error. A `Proc` that accepts `span` and `error` parameters. Sets error on the span by default. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

**Configuring clients to use different settings**

In situations where you have multiple clients calling multiple distinct services, you may pass the Datadog interceptor directly, like so

```ruby
configured_interceptor = Datadog::Tracing::Contrib::GRPC::DatadogInterceptor::Client.new do |c|
  c.service_name = "Alternate"
end

alternate_client = Demo::Echo::Service.rpc_stub_class.new(
  'localhost:50052',
  :this_channel_is_insecure,
  :interceptors => [configured_interceptor]
)
```

The integration will ensure that the `configured_interceptor` establishes a unique tracing setup for that client instance.

### http.rb

The http.rb integration will trace any HTTP call using the Http.rb gem.

```ruby
require 'http'
require 'ddtrace'
Datadog::Tracing.configure do |c|
  c.instrument :httprb, options
  # optionally, specify a different service name for hostnames matching a regex
  c.instrument :httprb, describes: /user-[^.]+\.example\.com/ do |httprb|
    httprb.service_name = 'user.example.com'
    httprb.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `service_name` | Service name for `httprb` instrumentation. | `'httprb'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |

### httpclient

The httpclient integration will trace any HTTP call using the httpclient gem.

```ruby
require 'httpclient'
require 'ddtrace'
Datadog::Tracing.configure do |c|
  c.instrument :httpclient, options
  # optionally, specify a different service name for hostnames matching a regex
  c.instrument :httpclient, describes: /user-[^.]+\.example\.com/ do |httpclient|
    httpclient.service_name = 'user.example.com'
    httpclient.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `service_name` | Service name for `httpclient` instrumentation. | `'httpclient'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |

### httpx

`httpx` maintains its [own integration with `ddtrace`](https://honeyryderchuck.gitlab.io/httpx/wiki/Datadog-Adapter):

```ruby
require "ddtrace"
require "httpx/adapters/datadog"

Datadog::Tracing.configure do |c|
  c.instrument :httpx

  # optionally, specify a different service name for hostnames matching a regex
  c.instrument :httpx, describes: /user-[^.]+\.example\.com/ do |http|
    http.service_name = 'user.example.com'
    http.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end
```

### Kafka

The Kafka integration provides tracing of the `ruby-kafka` gem:

You can enable it through `Datadog::Tracing.configure`:

```ruby
require 'active_support/notifications' # required to enable 'ruby-kafka' instrumentation
require 'kafka'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :kafka
end
```

### MongoDB

The integration traces any `Command` that is sent from the [MongoDB Ruby Driver](https://github.com/mongodb/mongo-ruby-driver) to a MongoDB cluster. By extension, Object Document Mappers (ODM) such as Mongoid are automatically instrumented if they use the official Ruby driver. To activate the integration, simply:

```ruby
require 'mongo'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :mongo, options
end

# Create a MongoDB client and use it as usual
client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'artists')
collection = client[:people]
collection.insert_one({ name: 'Steve' })

# In case you want to override the global configuration for a certain client instance
Datadog.configure_onto(client, **options)
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `quantize` | Hash containing options for quantization. May include `:show` with an Array of keys to not quantize (or `:all` to skip quantization), or `:exclude` with Array of keys to exclude entirely. | `{ show: [:collection, :database, :operation] }` |
| `service_name` | Service name used for `mongo` instrumentation | `'mongodb'` |

**Configuring trace settings per connection**

You can configure trace settings per connection by using the `describes` option:

```ruby
# Provide a `:describes` option with a connection key.
# Any of the following keys are acceptable and equivalent to one another.
# If a block is provided, it yields a Settings object that
# accepts any of the configuration options listed above.

Datadog::Tracing.configure do |c|
  # Network connection string
  c.instrument :mongo, describes: '127.0.0.1:27017', service_name: 'mongo-primary'

  # Network connection regular expression
  c.instrument :mongo, describes: /localhost.*/, service_name: 'mongo-secondary'
end

client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'artists')
collection = client[:people]
collection.insert_one({ name: 'Steve' })
# Traced call will belong to `mongo-primary` service

client = Mongo::Client.new([ 'localhost:27017' ], :database => 'artists')
collection = client[:people]
collection.insert_one({ name: 'Steve' })
# Traced call will belong to `mongo-secondary` service
```

When multiple `describes` configurations match a connection, the latest configured rule that matches will be applied.

### MySQL2

The MySQL2 integration traces any SQL command sent through `mysql2` gem.

```ruby
require 'mysql2'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :mysql2, options
end

client = Mysql2::Client.new(:host => "localhost", :username => "root")
client.query("SELECT * FROM users WHERE group='x'")
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `mysql2` instrumentation | `'mysql2'` |

### Net/HTTP

The Net/HTTP integration will trace any HTTP call using the standard lib Net::HTTP module.

```ruby
require 'net/http'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :http, options

  # optionally, specify a different service name for hostnames matching a regex
  c.instrument :http, describes: /user-[^.]+\.example\.com/ do |http|
    http.service_name = 'user.example.com'
    http.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end

Net::HTTP.start('127.0.0.1', 8080) do |http|
  request = Net::HTTP::Get.new '/index'
  response = http.request(request)
end

content = Net::HTTP.get(URI('http://127.0.0.1/index.html'))
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `service_name` | Service name used for `http` instrumentation | `'net/http'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |

If you wish to configure each connection object individually, you may use the `Datadog.configure_onto` as it follows:

```ruby
client = Net::HTTP.new(host, port)
Datadog.configure_onto(client, **options)
```

### Presto

The Presto integration traces any SQL command sent through `presto-client` gem.

```ruby
require 'presto-client'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :presto, options
end

client = Presto::Client.new(
  server: "localhost:8880",
  ssl: {verify: false},
  catalog: "native",
  schema: "default",
  time_zone: "US/Pacific",
  language: "English",
  http_debug: true,
)

client.run("select * from system.nodes")
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `presto` instrumentation | `'presto'` |

### Qless

The Qless integration uses lifecycle hooks to trace job executions.

To add tracing to a Qless job:

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :qless, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `tag_job_data` | Enable tagging with job arguments. true for on, false for off. | `false` |
| `tag_job_tags` | Enable tagging with job tags. true for on, false for off. | `false` |

### Que

The Que integration is a middleware which will trace job executions.

You can enable it through `Datadog::Tracing.configure`:

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :que, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Que should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `tag_args` | Enable tagging of a job's args field. `true` for on, `false` for off. | `false` |
| `tag_data` | Enable tagging of a job's data field. `true` for on, `false` for off. | `false` |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Racecar

The Racecar integration provides tracing for Racecar jobs.

You can enable it through `Datadog::Tracing.configure`:

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :racecar, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `racecar` instrumentation | `'racecar'` |

### Rack

The Rack integration provides a middleware that traces all requests before they reach the underlying framework or application. It responds to the Rack minimal interface, providing reasonable values that can be retrieved at the Rack level.

This integration is automatically activated with web frameworks like Rails. If you're using a plain Rack application, enable the integration it to your `config.ru`:

```ruby
# config.ru example
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :rack, options
end

use Datadog::Tracing::Contrib::Rack::TraceMiddleware

app = proc do |env|
  [ 200, {'Content-Type' => 'text/plain'}, ['OK'] ]
end

run app
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `application` | Your Rack application. Required for `middleware_names`. | `nil` |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) so that this service trace is connected with a trace of another service if tracing headers are received | `true` |
| `headers` | Hash of HTTP request or response headers to add as tags to the `rack.request`. Accepts `request` and `response` keys with Array values e.g. `['Last-Modified']`. Adds `http.request.headers.*` and `http.response.headers.*` tags respectively. | `{ response: ['Content-Type', 'X-Request-ID'] }` |
| `middleware_names` | Enable this if you want to use the last executed middleware class as the resource name for the `rack` span. If enabled alongside the `rails` instrumention, `rails` takes precedence by setting the `rack` resource name to the active `rails` controller when applicable. Requires `application` option to use. | `false` |
| `quantize` | Hash containing options for quantization. May include `:query` or `:fragment`. | `{}` |
| `quantize.query` | Hash containing options for query portion of URL quantization. May include `:show` or `:exclude`. See options below. Option must be nested inside the `quantize` option. | `{}` |
| `quantize.query.show` | Defines which values should always be shown. Shows no values by default. May be an Array of strings, or `:all` to show all values. Option must be nested inside the `query` option. | `nil` |
| `quantize.query.exclude` | Defines which values should be removed entirely. Excludes nothing by default. May be an Array of strings, or `:all` to remove the query string entirely. Option must be nested inside the `query` option. | `nil` |
| `quantize.fragment` | Defines behavior for URL fragments. Removes fragments by default. May be `:show` to show URL fragments. Option must be nested inside the `quantize` option. | `nil` |
| `request_queuing` | Track HTTP request time spent in the queue of the frontend server. See [HTTP request queuing](#http-request-queuing) for setup details. Set to `true` to enable. | `false` |
| `web_service_name` | Service name for frontend server request queuing spans. (e.g. `'nginx'`) | `'web-server'` |

**Configuring URL quantization behavior**

```ruby
Datadog::Tracing.configure do |c|
  # Default behavior: all values are quantized, fragment is removed.
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id&sort_by
  # http://example.com/path?categories[]=1&categories[]=2 --> http://example.com/path?categories[]

  # Show values for any query string parameter matching 'category_id' exactly
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id=1&sort_by
  c.instrument :rack, quantize: { query: { show: ['category_id'] } }

  # Show all values for all query string parameters
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id=1&sort_by=asc
  c.instrument :rack, quantize: { query: { show: :all } }

  # Totally exclude any query string parameter matching 'sort_by' exactly
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id
  c.instrument :rack, quantize: { query: { exclude: ['sort_by'] } }

  # Remove the query string entirely
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path
  c.instrument :rack, quantize: { query: { exclude: :all } }

  # Show URL fragments
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id&sort_by#featured
  c.instrument :rack, quantize: { fragment: :show }
end
```

### Rails

The Rails integration will trace requests, database calls, templates rendering, and cache read/write/delete operations. The integration makes use of the Active Support Instrumentation, listening to the Notification API so that any operation instrumented by the API is traced.

To enable the Rails instrumentation, create an initializer file in your `config/initializers` folder:

```ruby
# config/initializers/datadog.rb
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :rails, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `cache_service` | Cache service name used when tracing cache activity | `'<app_name>-cache'` |
| `database_service` | Database service name used when tracing database activity | `'<app_name>-<adapter_name>'` |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) so that this service trace is connected with a trace of another service if tracing headers are received | `true` |
| `exception_controller` | Class or Module which identifies a custom exception controller class. Tracer provides improved error behavior when it can identify custom exception controllers. By default, without this option, it 'guesses' what a custom exception controller looks like. Providing this option aids this identification. | `nil` |
| `middleware` | Add the trace middleware to the Rails application. Set to `false` if you don't want the middleware to load. | `true` |
| `middleware_names` | Enables any short-circuited middleware requests to display the middleware name as a resource for the trace. | `false` |
| `service_name` | Service name used when tracing application requests (on the `rack` level) | `'<app_name>'` (inferred from your Rails application namespace) |
| `template_base_path` | Used when the template name is parsed. If you don't store your templates in the `views/` folder, you may need to change this value | `'views/'` |

**Supported versions**

| MRI Versions  | JRuby Versions | Rails Versions |
| ------------- | -------------- | -------------- |
|  2.1          |                |  3.2 - 4.2     |
|  2.2 - 2.3    |                |  3.2 - 5.2     |
|  2.4          |                |  4.2.8 - 5.2   |
|  2.5          |                |  4.2.8 - 6.1   |
|  2.6 - 2.7    |  9.2           |  5.0 - 6.1     |
|  3.0          |                |  6.1           |

### Rake

You can add instrumentation around your Rake tasks by activating the `rake` integration. Each task and its subsequent subtasks will be traced.

To activate Rake task tracing, add the following to your `Rakefile`:

```ruby
# At the top of your Rakefile:
require 'rake'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :rake, options
end

task :my_task do
  # Do something task work here...
end

Rake::Task['my_task'].invoke
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Rake tasks should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `quantize` | Hash containing options for quantization of task arguments. See below for more details and examples. | `{}` |

**Configuring task quantization behavior**

```ruby
Datadog::Tracing.configure do |c|
  # Given a task that accepts :one, :two, :three...
  # Invoked with 'foo', 'bar', 'baz'.

  # Default behavior: all arguments are quantized.
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> { one: '?', two: '?', three: '?' }
  c.instrument :rake

  # Show values for any argument matching :two exactly
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> { one: '?', two: 'bar', three: '?' }
  c.instrument :rake, quantize: { args: { show: [:two] } }

  # Show all values for all arguments.
  # `rake.invoke.args` tag  --> ['foo', 'bar', 'baz']
  # `rake.execute.args` tag --> { one: 'foo', two: 'bar', three: 'baz' }
  c.instrument :rake, quantize: { args: { show: :all } }

  # Totally exclude any argument matching :three exactly
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> { one: '?', two: '?' }
  c.instrument :rake, quantize: { args: { exclude: [:three] } }

  # Remove the arguments entirely
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> {}
  c.instrument :rake, quantize: { args: { exclude: :all } }
end
```

### Redis

The Redis integration will trace simple calls as well as pipelines.

```ruby
require 'redis'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :redis, options
end

# Perform Redis commands
redis = Redis.new
redis.set 'foo', 'bar'
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `redis` instrumentation | `'redis'` |
| `command_args` | Show the command arguments (e.g. `key` in `GET key`) as resource name and tag | true |

You can also set *per-instance* configuration as it follows:

```ruby
require 'redis'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :redis # Enabling integration instrumentation is still required
end

customer_cache = Redis.new
invoice_cache = Redis.new

Datadog.configure_onto(customer_cache, service_name: 'customer-cache')
Datadog.configure_onto(invoice_cache, service_name: 'invoice-cache')

# Traced call will belong to `customer-cache` service
customer_cache.get(...)
# Traced call will belong to `invoice-cache` service
invoice_cache.get(...)
```

**Configuring trace settings per connection**

You can configure trace settings per connection by using the `describes` option:

```ruby
# Provide a `:describes` option with a connection key.
# Any of the following keys are acceptable and equivalent to one another.
# If a block is provided, it yields a Settings object that
# accepts any of the configuration options listed above.

Datadog::Tracing.configure do |c|
  # The default configuration for any redis client
  c.instrument :redis, service_name: 'redis-default'

  # The configuration matching a given unix socket.
  c.instrument :redis, describes: { url: 'unix://path/to/file' }, service_name: 'redis-unix'

  # For network connections, only these fields are considered during matching:
  # scheme, host, port, db
  # Other fields are ignored.

  # Network connection string
  c.instrument :redis, describes: 'redis://127.0.0.1:6379/0', service_name: 'redis-connection-string'
  c.instrument :redis, describes: { url: 'redis://127.0.0.1:6379/1' }, service_name: 'redis-connection-url'
  # Network client hash
  c.instrument :redis, describes: { host: 'my-host.com', port: 6379, db: 1, scheme: 'redis' }, service_name: 'redis-connection-hash'
  # Only a subset of the connection hash
  c.instrument :redis, describes: { host: ENV['APP_CACHE_HOST'], port: ENV['APP_CACHE_PORT'] }, service_name: 'redis-cache'
  c.instrument :redis, describes: { host: ENV['SIDEKIQ_CACHE_HOST'] }, service_name: 'redis-sidekiq'
end
```

When multiple `describes` configurations match a connection, the latest configured rule that matches will be applied.

### Resque

The Resque integration uses Resque hooks that wraps the `perform` method.

To add tracing to a Resque job:

```ruby
require 'resque'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :resque, **options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Rest Client

The `rest-client` integration is available through the `ddtrace` middleware:

```ruby
require 'rest_client'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :rest_client, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `service_name` | Service name for `rest_client` instrumentation. | `'rest_client'` |

### RSpec

RSpec integration will trace all executions of example groups and examples when using `rspec` test framework.

To activate your integration, use the `Datadog::Tracing.configure` method:

```ruby
require 'rspec'
require 'ddtrace'

# Configure default RSpec integration
Datadog::Tracing.configure do |c|
  c.instrument :rspec, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether RSpec tests should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `service_name` | Service name used for `rspec` instrumentation. | `'rspec'` |
| `operation_name` | Operation name used for `rspec` instrumentation. Useful if you want rename automatic trace metrics e.g. `trace.#{operation_name}.errors`. | `'rspec.example'` |

### Sequel

The Sequel integration traces queries made to your database.

```ruby
require 'sequel'
require 'ddtrace'

# Connect to database
database = Sequel.sqlite

# Create a table
database.create_table :articles do
  primary_key :id
  String :name
end

Datadog::Tracing.configure do |c|
  c.instrument :sequel, options
end

# Perform a query
articles = database[:articles]
articles.all
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name for `sequel` instrumentation | Name of database adapter (e.g. `'mysql2'`) |

**Configuring databases to use different settings**

If you use multiple databases with Sequel, you can give each of them different settings by configuring their respective `Sequel::Database` objects:

```ruby
sqlite_database = Sequel.sqlite
postgres_database = Sequel.connect('postgres://user:password@host:port/database_name')

# Configure each database with different service names
Datadog.configure_onto(sqlite_database, service_name: 'my-sqlite-db')
Datadog.configure_onto(postgres_database, service_name: 'my-postgres-db')
```

### Shoryuken

The Shoryuken integration is a server-side middleware which will trace job executions.

You can enable it through `Datadog::Tracing.configure`:

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :shoryuken, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `tag_body` | Tag spans with the SQS message body `true` or `false` | `false` |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Sidekiq

The Sidekiq integration is a client-side & server-side middleware which will trace job queuing and executions respectively.

You can enable it through `Datadog::Tracing.configure`:

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :sidekiq, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `tag_args` | Enable tagging of job arguments. `true` for on, `false` for off. | `false` |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Sinatra

The Sinatra integration traces requests and template rendering.

To start using the tracing client, make sure you import `ddtrace` and `use :sinatra` after either `sinatra` or `sinatra/base`, and before you define your application/routes:

#### Classic application

```ruby
require 'sinatra'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :sinatra, options
end

get '/' do
  'Hello world!'
end
```

#### Modular application

```ruby
require 'sinatra/base'
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :sinatra, options
end

class NestedApp < Sinatra::Base
  register Datadog::Tracing::Contrib::Sinatra::Tracer

  get '/nested' do
    'Hello from nested app!'
  end
end

class App < Sinatra::Base
  register Datadog::Tracing::Contrib::Sinatra::Tracer

  use NestedApp

  get '/' do
    'Hello world!'
  end
end
```

Ensure you register `Datadog::Tracing::Contrib::Sinatra::Tracer` as a middleware before you mount your nested applications.

#### Instrumentation options

`options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) so that this service trace is connected with a trace of another service if tracing headers are received | `true` |
| `headers` | Hash of HTTP request or response headers to add as tags to the `sinatra.request`. Accepts `request` and `response` keys with Array values e.g. `['Last-Modified']`. Adds `http.request.headers.*` and `http.response.headers.*` tags respectively. | `{ response: ['Content-Type', 'X-Request-ID'] }` |
| `resource_script_names` | Prepend resource names with script name | `false` |

### Sneakers

The Sneakers integration is a server-side middleware which will trace job executions.

You can enable it through `Datadog::Tracing.configure`:

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :sneakers, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Sneakers should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `tag_body` | Enable tagging of job message. `true` for on, `false` for off. | `false` |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Sucker Punch

The `sucker_punch` integration traces all scheduled jobs:

```ruby
require 'ddtrace'

Datadog::Tracing.configure do |c|
  c.instrument :sucker_punch
end

# Execution of this job is traced
LogJob.perform_async('login')
```

## Advanced configuration

### Environment variables

- `DD_AGENT_HOST`: Hostname of agent to where traces will be sent. See [Tracer settings](#tracer-settings) for more details.
- `DD_ENV`: Your application environment. See [Environment and tags](#environment-and-tags) for more details.
- `DD_LOGS_INJECTION`: Injects [Trace Correlation](#trace-correlation) information into Rails logs, if present. Supports the default logger (`ActiveSupport::TaggedLogging`), `lograge`, and `semantic_logger`. Valid values are: `true` (default) or `false`. e.g. `DD_LOGS_INJECTION=false`.
- `DD_PROPAGATION_STYLE_EXTRACT`: Distributed tracing header formats to extract. See [Distributed Tracing](#distributed-tracing) for more details.
- `DD_PROPAGATION_STYLE_INJECT`: Distributed tracing header formats to inject. See [Distributed Tracing](#distributed-tracing) for more details.
- `DD_SERVICE`: Your application's default service name. See [Environment and tags](#environment-and-tags) for more details.
- `DD_TAGS`: Custom tags for telemetry produced by your application. See [Environment and tags](#environment-and-tags) for more details.
- `DD_TRACE_<INTEGRATION>_ENABLED`: Enables or disables an **activated** integration. Defaults to `true`.. e.g. `DD_TRACE_RAILS_ENABLED=false`. This option has no effects on integrations that have not been explicitly activated (e.g. `Datadog::Tracing.configure { |c| c.instrument :integration }`).on code. This environment variable can only be used to disable an integration.
- `DD_TRACE_AGENT_PORT`: Port to where traces will be sent. See [Tracer settings](#tracer-settings) for more details.
- `DD_TRACE_AGENT_URL`: Sets the URL endpoint where traces are sent. Has priority over `DD_AGENT_HOST` and `DD_TRACE_AGENT_PORT` if set. e.g. `DD_TRACE_AGENT_URL=http://localhost:8126`.
- `DD_TRACE_ANALYTICS_ENABLED`: Enables or disables trace analytics. See [Sampling](#sampling) for more details.
- `DD_TRACE_RATE_LIMIT`: Sets a rate limit for sampling. See [Sampling](#sampling) for more details.
- `DD_TRACE_REPORT_HOSTNAME`: Enables ot disables hostname tags on traces.
- `DD_TRACE_SAMPLE_RATE`: Sets the trace sampling rate between `0.0` (0%) and `1.0` (100%, recommended). `1.0` or Tracing without Limits™, allows you to send all of your traffic and retention can be [configured within the Datadog app](https://docs.datadoghq.com/tracing/trace_retention_and_ingestion/). When this configuration is not set, the Datadog agent will keep an intelligent assortment of diverse traces.
- `DD_TRACE_TEST_MODE_ENABLED`: Enables or disables test mode, for use of tracing in test suites.
- `DD_VERSION`: Your application version. See [Environment and tags](#environment-and-tags) for more details.

### Global settings

```ruby
# config/initializers/datadog-tracer.rb
Datadog.configure do |c|
  c.agent.host = 'custom-agent-host'
  c.agent.port = 8126
end
```

Available options are:

- `agent.host`: set the hostname of the trace agent. Defaults to `127.0.0.1`.
- `agent.port`: set the APM TCP port the Datadog Agent listening on. Defaults to `8126`.

#### Custom logging

By default, all logs are processed by the default Ruby logger. When using Rails, you should see the messages in your application log file.

Datadog client log messages are marked with `[ddtrace]` so you should be able to isolate them from other messages.

Additionally, it is possible to override the default logger and replace it by a custom one. This is done using the `log` setting.

```ruby
f = File.new("my-custom.log", "w+") # Log messages should go there
Datadog.configure do |c|
  c.logger.instance = Logger.new(f) # Overriding the default logger
  c.logger.level = ::Logger::INFO
end

Datadog.logger.info { "this is typically called by tracing code" }
```

#### Environment and tags

By default, the trace agent (not this library, but the program running in the background collecting data from various clients) uses the tags set in the agent config file, see our [environments tutorial](https://app.datadoghq.com/apm/docs/tutorials/environments) for details.

You can configure the application to automatically tag your traces and metrics, using the following environment variables:

 - `DD_ENV`: Your application environment (e.g. `production`, `staging`, etc.)
 - `DD_SERVICE`: Your application's default service name (e.g. `billing-api`)
 - `DD_VERSION`: Your application version (e.g. `2.5`, `202003181415`, `1.3-alpha`, etc.)
 - `DD_TAGS`: Custom tags in value pairs separated by `,` (e.g. `layer:api,team:intake`)
    - If `DD_ENV`, `DD_SERVICE` or `DD_VERSION` are set, it will override any respective `env`/`service`/`version` tag defined in `DD_TAGS`.
    - If `DD_ENV`, `DD_SERVICE` or `DD_VERSION` are NOT set, tags defined in `DD_TAGS` will be used to populate `env`/`service`/`version` respectively.

These values can also be overridden at the tracer level:

```ruby
Datadog.configure do |c|
  c.service = 'billing-api'
  c.env = 'test'
  c.tags = { 'team' => 'qa' }
  c.version = '1.3-alpha'
end
```

This enables you to set this value on a per application basis, so you can have for example several applications reporting for different environments on the same host.

Tags can also be set directly on individual spans, which will supersede any conflicting tags defined at the application level.

#### Debugging and diagnostics

You can activate debugging features by using `Datadog.configure`:

```ruby
# config/initializers/datadog-tracer.rb

# Global settings are set here:
Datadog.configure do |c|
  # To enable debug mode
  c.diagnostics.debug = true
end
```

Available options are:

 - `diagnostics.debug`: set to true to enable debug logging. Can be configured through the `DD_TRACE_DEBUG` environment variable. Defaults to `false`.
 - `diagnostics.startup_logs.enabled`: Startup configuration and diagnostic log. Defaults to `true`. Can be configured through the `DD_TRACE_STARTUP_LOGS` environment variable.
 - `time_now_provider`: when testing, it might be helpful to use a different time provider. For Timecop, for example, `->{ Time.now_without_mock_time }` allows the tracer to use the real wall time. Span duration calculation will still use the system monotonic clock when available, thus not being affected by this setting. Defaults to `->{ Time.now }`.

### Tracer settings

To change the default behavior of the Datadog tracer, you can provide custom options inside the `Datadog::Tracing.configure` block as in:

```ruby
# config/initializers/datadog-tracer.rb
# Tracer settings are set here:
Datadog::Tracing.configure do |c|
  c.tracer.enabled = true

  # Ensure all traces are ingested by Datadog
  c.sampling.default_rate = 1.0 # Recommended
  c.sampling.rate_limit = 200
  # or provide a custom implementation (overrides c.sampling settings)
  c.tracer.sampler = Datadog::Tracing::Sampling::AllSampler.new

  # Breaks down very large traces into smaller batches
  c.tracer.partial_flush.enabled = false

  # You can specify your own tracer
  c.tracer.instance = Datadog::Tracing::Tracer.new
end
```

Available options are:

 - `log_injection`: Injects [Trace Correlation](#trace-correlation) information into Rails logs, if present. Defaults to `true`.
 - `sampling.default_rate`: default tracer sampling rate, between `0.0` (0%) and `1.0` (100%, recommended). `1.0` or Tracing without Limits™, allows you to send all of your traffic and retention can be [configured within the Datadog app](https://docs.datadoghq.com/tracing/trace_retention_and_ingestion/). When this configuration is not set, the Datadog agent will keep an intelligent assortment of diverse traces.
 - `sampling.rate_limit`: maximum number of traces per second to sample. Defaults to 100 per second.
 - `tracer.enabled`: defines if the `tracer` is enabled or not. If set to `false` instrumentation will still run, but no spans are sent to the trace agent. Can be configured through the `DD_TRACE_ENABLED` environment variable. Defaults to `true`.
 - `tracer.instance`: set to a custom `Datadog::Tracer` instance. If provided, other trace settings are ignored (you must configure it manually.)
 - `tracer.partial_flush.enabled`: set to `true` to enable partial trace flushing (for long running traces.) Disabled by default. *Experimental.*
 - `tracer.sampler`: set to a custom `Datadog::Sampler` instance. If provided, the tracer will use this sampler to determine sampling behavior.

### Sampling

Datadog's Tracing without Limits™ allows you to send all of your traffic and [configure retention within the Datadog app](https://docs.datadoghq.com/tracing/trace_retention_and_ingestion/).

We recommend setting the environment variable `DD_TRACE_SAMPLE_RATE=1.0` in all new applications using `ddtrace`.

App Analytics, previously configured with the `analytics.enabled` setting, is deprecated in favor of Tracing without Limits™. Documentation for this [deprecated configuration is still available](https://docs.datadoghq.com/tracing/legacy_app_analytics/).

#### Application-side sampling

While the trace agent can sample traces to reduce bandwidth usage, application-side sampling reduces the performance overhead.

This will **reduce visibility and is not recommended**. See [DD_TRACE_SAMPLE_RATE](#environment-variables) for the recommended sampling approach.

`Datadog::Tracing::Sampling::RateSampler` samples a ratio of the traces. For example:

```ruby
# Sample rate is between 0 (nothing sampled) to 1 (everything sampled).
sampler = Datadog::Tracing::Sampling::RateSampler.new(0.5) # sample 50% of the traces

Datadog::Tracing.configure do |c|
  c.tracer.sampler = sampler
end
```

#### Priority sampling

Priority sampling decides whether to keep a trace by using a priority attribute propagated for distributed traces. Its value indicates to the Agent and the backend about how important the trace is.

The sampler can set the priority to the following values:

 - `Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT`: the sampler automatically decided to reject the trace.
 - `Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP`: the sampler automatically decided to keep the trace.

Priority sampling is enabled by default. Enabling it ensures that your sampled distributed traces will be complete. Once enabled, the sampler will automatically assign a priority of 0 or 1 to traces, depending on their service and volume.

You can also set this priority manually to either drop a non-interesting trace or to keep an important one. For that, set the `TraceOperation#sampling_priority` to:

 - `Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT`: the user asked to reject the trace.
 - `Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP`: the user asked to keep the trace.

When not using [distributed tracing](#distributed-tracing), you may change the priority at any time, as long as the trace incomplete. But it has to be done before any context propagation (fork, RPC calls) to be useful in a distributed context. Changing the priority after the context has been propagated causes different parts of a distributed trace to use different priorities. Some parts might be kept, some parts might be rejected, and this can cause the trace to be partially stored and remain incomplete.

For this reason, if you change the priority, we recommend you do it as early as possible.

To change the sampling priority, you can use the following methods:

```ruby
# Rejects the active trace
Datadog::Tracing.reject!

# Keeps the active trace
Datadog::Tracing.keep!
```

It's safe to use `Datadog::Tracing.reject!` and `Datadog::Tracing.keep!` when no trace is active.

You can also reject a specific trace instance:

```ruby
# First, grab the active span
trace = Datadog::Tracing.active_trace

# Rejects the trace
trace.reject!

# Keeps the trace
trace.keep!
```

### Distributed Tracing

Distributed tracing allows traces to be propagated across multiple instrumented applications so that a request can be presented as a single trace, rather than a separate trace per service.

To trace requests across application boundaries, the following must be propagated between each application:

| Property              | Type    | Description                                                                                                                 |
| --------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------- |
| **Trace ID**          | Integer | ID of the trace. This value should be the same across all requests that belong to the same trace.                           |
| **Parent Span ID**    | Integer | ID of the span in the service originating the request. This value will always be different for each request within a trace. |
| **Sampling Priority** | Integer | Sampling priority level for the trace. This value should be the same across all requests that belong to the same trace.     |

Such propagation can be visualized as:

```
Service A:
  Trace ID:  100000000000000001
  Parent ID: 0
  Span ID:   100000000000000123
  Priority:  1

  |
  | Service B Request:
  |   Metadata:
  |     Trace ID:  100000000000000001
  |     Parent ID: 100000000000000123
  |     Priority:  1
  |
  V

Service B:
  Trace ID:  100000000000000001
  Parent ID: 100000000000000123
  Span ID:   100000000000000456
  Priority:  1

  |
  | Service C Request:
  |   Metadata:
  |     Trace ID:  100000000000000001
  |     Parent ID: 100000000000000456
  |     Priority:  1
  |
  V

Service C:
  Trace ID:  100000000000000001
  Parent ID: 100000000000000456
  Span ID:   100000000000000789
  Priority:  1
```

**Via HTTP**

For HTTP requests between instrumented applications, this trace metadata is propagated by use of HTTP Request headers:

| Property              | Type    | HTTP Header name              |
| --------------------- | ------- | ----------------------------- |
| **Trace ID**          | Integer | `x-datadog-trace-id`          |
| **Parent Span ID**    | Integer | `x-datadog-parent-id`         |
| **Sampling Priority** | Integer | `x-datadog-sampling-priority` |

Such that:

```
Service A:
  Trace ID:  100000000000000001
  Parent ID: 0
  Span ID:   100000000000000123
  Priority:  1

  |
  | Service B HTTP Request:
  |   Headers:
  |     x-datadog-trace-id:          100000000000000001
  |     x-datadog-parent-id:         100000000000000123
  |     x-datadog-sampling-priority: 1
  |
  V

Service B:
  Trace ID:  100000000000000001
  Parent ID: 100000000000000123
  Span ID:   100000000000000456
  Priority:  1

  |
  | Service C HTTP Request:
  |   Headers:
  |     x-datadog-trace-id:          100000000000000001
  |     x-datadog-parent-id:         100000000000000456
  |     x-datadog-sampling-priority: 1
  |
  V

Service C:
  Trace ID:  100000000000000001
  Parent ID: 100000000000000456
  Span ID:   100000000000000789
  Priority:  1
```

**Distributed header formats**

Tracing supports the following distributed trace formats:

 - `Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG` (Default)
 - `Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3`
 - `Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER`

You can enable/disable the use of these formats via `Datadog::Tracing.configure`:

```ruby
Datadog::Tracing.configure do |c|
  # List of header formats that should be extracted
  c.distributed_tracing.propagation_extract_style = [
    Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG,
    Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3,
    Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER

  ]

  # List of header formats that should be injected
  c.distributed_tracing.propagation_inject_style = [
    Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG
  ]
end
```

**Activating distributed tracing for integrations**

Many integrations included in `ddtrace` support distributed tracing. Distributed tracing is enabled by default in Agent v7 and most versions of Agent v6. If needed, you can activate distributed tracing with configuration settings.

- If your application receives requests from services with distributed tracing activated, you must activate distributed tracing on the integrations that handle these requests (e.g. Rails)
- If your application send requests to services with distributed tracing activated, you must activate distributed tracing on the integrations that send these requests (e.g. Faraday)
- If your application both sends and receives requests implementing distributed tracing, it must activate all integrations that handle these requests.

For more details on how to activate distributed tracing for integrations, see their documentation:

- [Excon](#excon)
- [Faraday](#faraday)
- [Rest Client](#rest-client)
- [Net/HTTP](#nethttp)
- [Rack](#rack)
- [Rails](#rails)
- [Sinatra](#sinatra)
- [http.rb](#httprb)
- [httpclient](#httpclient)
- [httpx](#httpx)

**Using the HTTP propagator**

To make the process of propagating this metadata easier, you can use the `Datadog::Tracing::Propagation::HTTP` module.

On the client:

```ruby
Datadog::Tracing.trace('web.call') do |span, trace|
  # Inject trace headers into request headers (`env` must be a Hash)
  Datadog::Tracing::Propagation::HTTP.inject!(trace.to_digest, env)
end
```

On the server:

```ruby
trace_digest = Datadog::Tracing::Propagation::HTTP.extract(request.env)

Datadog::Tracing.trace('web.work', continue_from: trace_digest) do |span|
  # Do web work...
end
```

### HTTP request queuing

Traces that originate from HTTP requests can be configured to include the time spent in a frontend web server or load balancer queue before the request reaches the Ruby application.

This feature is disabled by default. To activate it, you must add an `X-Request-Start` or `X-Queue-Start` header from your web server (i.e., Nginx). The following is an Nginx configuration example:

```
# /etc/nginx/conf.d/ruby_service.conf
server {
    listen 8080;

    location / {
      proxy_set_header X-Request-Start "t=${msec}";
      proxy_pass http://web:3000;
    }
}
```

Then you must enable the request queuing feature, by setting `request_queuing: true`, in the integration handling the request. For Rack-based applications, see the [documentation](#rack) for details.

### Processing Pipeline

Some applications might require that traces be altered or filtered out before they are sent to Datadog. The processing pipeline allows you to create *processors* to define such behavior.

#### Filtering

You can use the `Datadog::Tracing::Pipeline::SpanFilter` processor to remove spans, when the block evaluates as truthy:

```ruby
Datadog::Tracing.before_flush(
  # Remove spans that match a particular resource
  Datadog::Tracing::Pipeline::SpanFilter.new { |span| span.resource =~ /PingController/ },
  # Remove spans that are trafficked to localhost
  Datadog::Tracing::Pipeline::SpanFilter.new { |span| span.get_tag('host') == 'localhost' }
)
```

#### Processing

You can use the `Datadog::Tracing::Pipeline::SpanProcessor` processor to modify spans:

```ruby
Datadog::Tracing.before_flush(
  # Strip matching text from the resource field
  Datadog::Tracing::Pipeline::SpanProcessor.new { |span| span.resource.gsub!(/password=.*/, '') }
)
```

#### Custom processor

Processors can be any object that responds to `#call` accepting `trace` as an argument (which is an `Array` of `Datadog::Span`s.)

For example, using the short-hand block syntax:

```ruby
Datadog::Tracing.before_flush do |trace|
   # Processing logic...
   trace
end
```

For a custom processor class:

```ruby
class MyCustomProcessor
  def call(trace)
    # Processing logic...
    trace
  end
end

Datadog::Tracing.before_flush(MyCustomProcessor.new)
```

In both cases, the processor method *must* return the `trace` object; this return value will be passed to the next processor in the pipeline.

### Trace correlation

In many cases, such as logging, it may be useful to correlate trace IDs to other events or data streams, for easier cross-referencing.

#### For logging in Rails applications

##### Automatic

For Rails applications using the default logger (`ActiveSupport::TaggedLogging`), `lograge` or `semantic_logger`, trace correlation injection is enabled by default.

It can be disabled by setting the environment variable `DD_LOGS_INJECTION=false`.

#### For logging in Ruby applications

To add correlation IDs to your logger, add a log formatter which retrieves the correlation IDs with `Datadog::Tracing.correlation`, then add them to the message.

To properly correlate with Datadog logging, be sure the following is present in the log message, in order as they appear:

 - `dd.env=<ENV>`: Where `<ENV>` is equal to `Datadog::Tracing.correlation.env`. Omit if no environment is configured.
 - `dd.service=<SERVICE>`: Where `<SERVICE>` is equal to `Datadog::Tracing.correlation.service`. Omit if no default service name is configured.
 - `dd.version=<VERSION>`: Where `<VERSION>` is equal to `Datadog::Tracing.correlation.version`. Omit if no application version is configured.
 - `dd.trace_id=<TRACE_ID>`: Where `<TRACE_ID>` is equal to `Datadog::Tracing.correlation.trace_id` or `0` if no trace is active during logging.
 - `dd.span_id=<SPAN_ID>`: Where `<SPAN_ID>` is equal to `Datadog::Tracing.correlation.span_id` or `0` if no trace is active during logging.

`Datadog::Tracing.log_correlation` will return `dd.env=<ENV> dd.service=<SERVICE> dd.version=<VERSION> dd.trace_id=<TRACE_ID> dd.span_id=<SPAN_ID>`.

If a trace is not active and the application environment & version is not configured, it will return `dd.env= dd.service= dd.version= dd.trace_id=0 dd.span_id=0`.

An example of this in practice:

```ruby
require 'ddtrace'
require 'logger'

ENV['DD_ENV'] = 'production'
ENV['DD_SERVICE'] = 'billing-api'
ENV['DD_VERSION'] = '2.5.17'

logger = Logger.new(STDOUT)
logger.progname = 'my_app'
logger.formatter  = proc do |severity, datetime, progname, msg|
  "[#{datetime}][#{progname}][#{severity}][#{Datadog::Tracing.log_correlation}] #{msg}\n"
end

# When no trace is active
logger.warn('This is an untraced operation.')
# [2019-01-16 18:38:41 +0000][my_app][WARN][dd.env=production dd.service=billing-api dd.version=2.5.17 dd.trace_id=0 dd.span_id=0] This is an untraced operation.

# When a trace is active
Datadog::Tracing.trace('my.operation') { logger.warn('This is a traced operation.') }
# [2019-01-16 18:38:41 +0000][my_app][WARN][dd.env=production dd.service=billing-api dd.version=2.5.17 dd.trace_id=8545847825299552251 dd.span_id=3711755234730770098] This is a traced operation.
```

### Configuring the transport layer

By default, the tracer submits trace data using the Unix socket `/var/run/datadog/apm.socket`, if one is created by the Agent. Otherwise, it connects via HTTP to `127.0.0.1:8126`, the default TCP location the Agent listens on.

However, the tracer can be configured to send its trace data to alternative destinations, or by alternative protocols.

Some basic settings, such as hostname and port, can be configured using [tracer settings](#tracer-settings).

#### Using the Net::HTTP adapter

The `Net` adapter submits traces using `Net::HTTP` over TCP. It is the default transport adapter.

```ruby
Datadog::Tracing.configure do |c|
  c.tracer.transport_options = proc { |t|
    # Hostname, port, and additional options. :timeout is in seconds.
    t.adapter :net_http, '127.0.0.1', 8126, { timeout: 1 }
  }
end
```

#### Using the Unix socket adapter

The `UnixSocket` adapter submits traces using `Net::HTTP` over Unix socket.

To use, first configure your trace agent to listen by Unix socket, then configure the tracer with:

```ruby
Datadog::Tracing.configure do |c|
  c.tracer.transport_options = proc { |t|
    # Provide local path to trace agent Unix socket
    t.adapter :unix, '/tmp/ddagent/trace.sock'
  }
end
```

#### Using the transport test adapter

The `Test` adapter is a no-op transport that can optionally buffer requests. For use in test suites or other non-production environments.

```ruby
Datadog::Tracing.configure do |c|
  c.tracer.transport_options = proc { |t|
    # Set transport to no-op mode. Does not retain traces.
    t.adapter :test

    # Alternatively, you can provide a buffer to examine trace output.
    # The buffer must respond to '<<'.
    t.adapter :test, []
  }
end
```

#### Using a custom transport adapter

Custom adapters can be configured with:

```ruby
Datadog::Tracing.configure do |c|
  c.tracer.transport_options = proc { |t|
    # Initialize and pass an instance of the adapter
    custom_adapter = CustomAdapter.new
    t.adapter custom_adapter
  }
end
```

### Metrics

The tracer and its integrations can produce some additional metrics that can provide useful insight into the performance of your application. These metrics are collected with `dogstatsd-ruby`, and can be sent to the same Datadog agent to which you send your traces.

To configure your application for metrics collection:

1. [Configure your Datadog agent for StatsD](https://docs.datadoghq.com/developers/dogstatsd/#setup)
2. Add `gem 'dogstatsd-ruby', '~> 5.3'` to your Gemfile

#### For application runtime

If runtime metrics are configured, the trace library will automatically collect and send metrics about the health of your application.

To configure runtime metrics, add the following configuration:

```ruby
# config/initializers/datadog.rb
require 'datadog/statsd'
require 'ddtrace'

Datadog.configure do |c|
  # To enable runtime metrics collection, set `true`. Defaults to `false`
  # You can also set DD_RUNTIME_METRICS_ENABLED=true to configure this.
  c.runtime_metrics.enabled = true

  # Optionally, you can configure the Statsd instance used for sending runtime metrics.
  # Statsd is automatically configured with default settings if `dogstatsd-ruby` is available.
  # You can configure with host and port of Datadog agent; defaults to 'localhost:8125'.
  c.runtime_metrics.statsd = Datadog::Statsd.new
end
```

See the [Dogstatsd documentation](https://www.rubydoc.info/github/DataDog/dogstatsd-ruby/master/frames) for more details about configuring `Datadog::Statsd`.

The stats are VM specific and will include:

| Name                        | Type    | Description                                              | Available on |
| --------------------------  | ------- | -------------------------------------------------------- | ------------ |
| `runtime.ruby.class_count`  | `gauge` | Number of classes in memory space.                       | CRuby        |
| `runtime.ruby.gc.*`         | `gauge` | Garbage collection statistics: collected from `GC.stat`. | All runtimes |
| `runtime.ruby.thread_count` | `gauge` | Number of threads.                                       | All runtimes |
| `runtime.ruby.global_constant_state` | `gauge` | Global constant cache generation.               | CRuby        |
| `runtime.ruby.global_method_state`   | `gauge` | [Global method cache generation.](https://tenderlovemaking.com/2015/12/23/inline-caching-in-mri.html) | [CRuby < 3.0.0](https://docs.ruby-lang.org/en/3.0.0/NEWS_md.html#label-Implementation+improvements) |

In addition, all metrics include the following tags:

| Name         | Description                                             |
| ------------ | ------------------------------------------------------- |
| `language`   | Programming language traced. (e.g. `ruby`)              |
| `service`    | List of services this associated with this metric.      |

### OpenTracing

For setting up Datadog with OpenTracing, see out [Quickstart for OpenTracing](#quickstart-for-opentracing) section for details.

**Configuring Datadog tracer settings**

The underlying Datadog tracer can be configured by passing options (which match `Datadog::Tracer`) when configuring the global tracer:

```ruby
# Where `options` is a Hash of options provided to Datadog::Tracer
OpenTracing.global_tracer = Datadog::OpenTracer::Tracer.new(**options)
```

It can also be configured by using `Datadog::Tracing.configure` described in the [Tracer settings](#tracer-settings) section.

**Activating and configuring integrations**

By default, configuring OpenTracing with Datadog will not automatically activate any additional instrumentation provided by Datadog. You will only receive spans and traces from OpenTracing instrumentation you have in your application.

However, additional instrumentation provided by Datadog can be activated alongside OpenTracing using `Datadog.configure`, which can be used to enhance your tracing further. To activate this, see [Integration instrumentation](#integration-instrumentation) for more details.

**Supported serialization formats**

| Type                           | Supported? | Additional information |
| ------------------------------ | ---------- | ---------------------- |
| `OpenTracing::FORMAT_TEXT_MAP` | Yes        |                        |
| `OpenTracing::FORMAT_RACK`     | Yes        | Because of the loss of resolution in the Rack format, please note that baggage items with names containing either upper case characters or `-` will be converted to lower case and `_` in a round-trip respectively. We recommend avoiding these characters or accommodating accordingly on the receiving end. |
| `OpenTracing::FORMAT_BINARY`   | No         |                        |

### Profiling

*Currently available as BETA feature.*

`ddtrace` can produce profiles that measure method-level application resource usage within production environments. These profiles can give insight into resources spent in Ruby code outside of existing trace instrumentation.

**Setup**

To get started with profiling, follow the [Enabling the Ruby Profiler](https://docs.datadoghq.com/tracing/profiler/enabling/ruby/) guide.

#### Troubleshooting

If you run into issues with profiling, please check the [Profiler Troubleshooting Guide](https://docs.datadoghq.com/tracing/profiler/profiler_troubleshooting/?code-lang=ruby).

#### Profiling Resque jobs

When profiling [Resque](https://github.com/resque/resque) jobs, you should set the `RUN_AT_EXIT_HOOKS=1` option described in the [Resque](https://github.com/resque/resque/blob/v2.0.0/docs/HOOKS.md#worker-hooks) documentation.

Without this flag, profiles for short-lived Resque jobs will not be available as Resque kills worker processes before they have a chance to submit this information.

## Known issues and suggested configurations

### Payload too large

By default, Datadog limits the size of trace payloads to prevent memory overhead within instrumented applications. As a result, traces containing thousands of operations may not be sent to Datadog.

If traces are missing, enable [debug mode](#tracer-settings) to check if messages containing `"Dropping trace. Payload too large"` are logged.

Since debug mode is verbose, Datadog does not recommend leaving this enabled or enabling this in production. Disable it after confirming. You can inspect the [Datadog Agent logs](https://docs.datadoghq.com/agent/guide/agent-log-files/) for similar messages.

If you have confirmed that traces are dropped due to large payloads, then enable the [partial_flush](#tracer-settings) setting to break down large traces into smaller chunks.

### Stack level too deep

Datadog tracing collects trace data by adding instrumentation into other common libraries (e.g. Rails, Rack, etc.) Some libraries provide APIs to add this instrumentation, but some do not. In order to add instrumentation into libraries lacking an instrumentation API, Datadog uses a technique called "monkey-patching" to modify the code of that library.

In Ruby version 1.9.3 and earlier, "monkey-patching" often involved the use of [`alias_method`](https://ruby-doc.org/core-3.0.0/Module.html#method-i-alias_method), also known as *method rewriting*, to destructively replace existing Ruby methods. However, this practice would often create conflicts & errors if two libraries attempted to "rewrite" the same method. (e.g. two different APM packages trying to instrument the same method.)

In Ruby 2.0, the [`Module#prepend`](https://ruby-doc.org/core-3.0.0/Module.html#method-i-prepend) feature was introduced. This feature avoids destructive method rewriting and allows multiple "monkey patches" on the same method. Consequently, it has become the safest, preferred means to "monkey patch" code.

Datadog instrumentation almost exclusively uses the `Module#prepend` feature to add instrumentation non-destructively. However, some libraries (typically those supporting Ruby < 2.0) still use `alias_method` which can create conflicts with Datadog instrumentation, often resulting in `SystemStackError` or `stack level too deep` errors.

As the implementation of `alias_method` exists within those libraries, Datadog generally cannot fix them. However, some libraries have known workarounds:

* `rack-mini-profiler`: [Net::HTTP stack level too deep errors](https://github.com/MiniProfiler/rack-mini-profiler#nethttp-stack-level-too-deep-errors).

For libraries without a known workaround, consider removing the library using `alias` or `Module#alias_method` or separating libraries into different environments for testing.

For any further questions or to report an occurence of this issue, please [reach out to Datadog support](https://docs.datadoghq.com/help)
