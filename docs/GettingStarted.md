# Datadog Ruby Trace Client

`ddtrace` is Datadog’s tracing client for Ruby. It is used to trace requests as they flow across web servers,
databases and microservices so that developers have high visibility into bottlenecks and troublesome requests.

## Getting started

**If you're upgrading from a 0.x version, check out our [upgrade guide](https://github.com/DataDog/dd-trace-rb/blob/master/docs/UpgradeGuide.md#from-0x-to-10).**

For the general APM documentation, see our [setup documentation][setup docs].

For more information about what APM looks like once your application is sending information to Datadog, take a look at [Visualizing your APM data][visualization docs].

For the library API documentation, see our [YARD documentation][yard docs].

To contribute, check out the [contribution guidelines][contribution docs] and [development guide][development docs].

[setup docs]: https://docs.datadoghq.com/tracing/
[development docs]: https://github.com/DataDog/dd-trace-rb/blob/master/README.md#development
[visualization docs]: https://docs.datadoghq.com/tracing/visualization/
[contribution docs]: https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md
[development docs]: https://github.com/DataDog/dd-trace-rb/blob/master/docs/DevelopmentGuide.md
[yard docs]: https://www.rubydoc.info/gems/ddtrace/

## Table of Contents

 - [Compatibility](#compatibility)
 - [Installation](#installation)
     - [Setup the Datadog Agent for tracing](#setup-the-datadog-agent-for-tracing)
     - [Instrument your application](#instrument-your-application)
        - [Rails applications](#rails-applications)
        - [Ruby applications](#ruby-applications)
        - [Configuring OpenTracing](#configuring-opentracing)
        - [Configuring OpenTelemetry](#configuring-opentelemetry)
     - [Connect your application to the Datadog Agent](#connect-your-application-to-the-datadog-agent)
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
     - [hanami](#hanami)
     - [http.rb](#httprb)
     - [httpclient](#httpclient)
     - [httpx](#httpx)
     - [Kafka](#kafka)
     - [MongoDB](#mongodb)
     - [MySQL2](#mysql2)
     - [Net/HTTP](#nethttp)
     - [Postgres](#postgres)
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
     - [Stripe](#stripe)
     - [Sucker Punch](#sucker-punch)
 - [Additional configuration](#additional-configuration)
     - [Custom logging](#custom-logging)
     - [Environment and tags](#environment-and-tags)
     - [Debugging and diagnostics](#debugging-and-diagnostics)
     - [Sampling](#sampling)
         - [Application-side sampling](#application-side-sampling)
         - [Priority sampling](#priority-sampling)
         - [Single Span Sampling](#single-span-sampling)
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

<!--
    Note: Please replicate any changes to this section also to
    https://github.com/datadog/documentation/blob/master/content/en/tracing/setup_overview/compatibility_requirements/ruby.md
    so that they remain in sync.
-->

**Supported Ruby interpreters**:

| Type  | Documentation              | Version | Support type                         | Gem version support |
| ----- | -------------------------- | -----   | ------------------------------------ | ------------------- |
| MRI   | https://www.ruby-lang.org/ | 3.1     | Full                                 | Latest              |
|       |                            | 3.0     | Full                                 | Latest              |
|       |                            | 2.7     | Full                                 | Latest              |
|       |                            | 2.6     | Full                                 | Latest              |
|       |                            | 2.5     | Full                                 | Latest              |
|       |                            | 2.4     | Full                                 | Latest              |
|       |                            | 2.3     | Full                                 | Latest              |
|       |                            | 2.2     | Full (except for Profiling)          | Latest              |
|       |                            | 2.1     | Full (except for Profiling)          | Latest              |
|       |                            | 2.0     | EOL since June 7th, 2021             | < 0.50.0            |
|       |                            | 1.9.3   | EOL since August 6th, 2020           | < 0.27.0            |
|       |                            | 1.9.1   | EOL since August 6th, 2020           | < 0.27.0            |
| JRuby | https://www.jruby.org      | 9.3     | Full                                 | Latest              |
|       |                            | 9.2     | Full                                 | Latest              |

**Supported web servers**:

| Type      | Documentation                     | Version      | Support type |
| --------- | --------------------------------- | ------------ | ------------ |
| Puma      | http://puma.io/                   | 2.16+ / 3.6+ | Full         |
| Unicorn   | https://bogomips.org/unicorn/     | 4.8+ / 5.1+  | Full         |
| Passenger | https://www.phusionpassenger.com/ | 5.0+         | Full         |

**Supported tracing frameworks**:

| Type        | Documentation                                   | Version               | Gem version support |
| ----------- | ----------------------------------------------- | --------------------- | ------------------- |
| OpenTracing | https://github.com/opentracing/opentracing-ruby | 0.4.1+                | >= 0.16.0           |

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

Adding tracing to your Ruby application only takes a few quick steps:

1. Setup the Datadog Agent for tracing
2. Instrument your application
3. Connect your application to the Datadog Agent

### Setup the Datadog Agent for tracing

Before installing `ddtrace`, [install the Datadog Agent](https://docs.datadoghq.com/agent/), to which `ddtrace` will send trace data.

Then configure the Datadog Agent to accept traces. To do this, either:

 - Set `DD_APM_ENABLED=true` in the agent's environment

OR

 - Add `apm_enabled: true` to the [agent's configuration file](https://docs.datadoghq.com/agent/guide/agent-configuration-files/?tab=agentv6v7#agent-main-configuration-file)

*Additionally, in containerized environments...*

 - Set `DD_APM_NON_LOCAL_TRAFFIC=true` in the agent's environment

OR

 - Add `apm_non_local_traffic: true` to the [agent's configuration file](https://docs.datadoghq.com/agent/guide/agent-configuration-files/?tab=agentv6v7#agent-main-configuration-file).

See the specific setup instructions for [Docker](https://docs.datadoghq.com/agent/docker/apm/?tab=ruby), [Kubernetes](https://docs.datadoghq.com/agent/kubernetes/apm/?tab=helm), [Amazon ECS](https://docs.datadoghq.com/agent/amazon_ecs/apm/?tab=ruby) or [Fargate](https://docs.datadoghq.com/integrations/ecs_fargate/#trace-collection) to ensure that the Agent is configured to receive traces in a containerized environment.

#### Configuring trace data ingestion

The Datadog agent will listen for traces via HTTP on port `8126` by default.

You may change the protocol or port the agent listens for trace data using the following:

**For HTTP over TCP**:

 - Set `DD_APM_RECEIVER_PORT=<port>` in the agent's environment

OR

 - Add `apm_config: receiver_port: <port>` to the [agent's configuration file](https://docs.datadoghq.com/agent/guide/agent-configuration-files/?tab=agentv6v7#agent-main-configuration-file)

 **For Unix Domain Socket (UDS)**:

 - Set `DD_APM_RECEIVER_SOCKET=<path-to-socket-file>`

OR

 - Add `apm_config: receiver_socket: <path-to-socket-file>` to the [agent's configuration file](https://docs.datadoghq.com/agent/guide/agent-configuration-files/?tab=agentv6v7#agent-main-configuration-file)

### Instrument your application

#### Rails/Hanami applications

1. Add the `ddtrace` gem to your Gemfile:

    ```ruby
    source 'https://rubygems.org'
    gem 'ddtrace', require: 'ddtrace/auto_instrument'
    ```

2. Install the gem with `bundle install`

3. Create a `config/initializers/datadog.rb` file containing:

    ```ruby
    Datadog.configure do |c|
      # Add additional configuration here.
      # Activate integrations, change tracer settings, etc...
    end
    ```

    Using this block you can:

      - [Add additional configuration settings](#additional-configuration)
      - [Activate or reconfigure instrumentation](#integration-instrumentation)

#### Ruby applications

1. Add the `ddtrace` gem to your Gemfile:

    ```ruby
    source 'https://rubygems.org'
    gem 'ddtrace'
    ```

2. Install the gem with `bundle install`
3. `require` any [supported libraries or frameworks](#integration-instrumentation) that should be instrumented.
4. Add `require 'ddtrace/auto_instrument'` to your application. _Note:_ This must be done _after_ requiring any supported libraries or frameworks.

    ```ruby
    # Example frameworks and libraries
    require 'sinatra'
    require 'faraday'
    require 'redis'

    require 'ddtrace/auto_instrument'
    ```

5. Add a configuration block to your application:

    ```ruby
    Datadog.configure do |c|
      # Add additional configuration here.
      # Activate integrations, change tracer settings, etc...
    end
    ```

    Using this block you can:

      - [Add additional configuration settings](#additional-configuration)
      - [Activate or reconfigure instrumentation](#integration-instrumentation)

#### Configuring OpenTracing

1. Add the `ddtrace` gem to your Gemfile:

    ```ruby
    source 'https://rubygems.org'
    gem 'ddtrace'
    ```

2. Install the gem with `bundle install`
3. To your OpenTracing configuration file, add the following:

    ```ruby
    require 'opentracing'
    require 'datadog/tracing'
    require 'datadog/opentracer'

    # Activate the Datadog tracer for OpenTracing
    OpenTracing.global_tracer = Datadog::OpenTracer::Tracer.new
    ```

4. Add a configuration block to your application:

    ```ruby
    Datadog.configure do |c|
      # Configure the Datadog tracer here.
      # Activate integrations, change tracer settings, etc...
      # By default without additional configuration,
      # no additional integrations will be traced, only
      # what you have instrumented with OpenTracing.
    end
    ```

     Using this block you can:

      - [Add additional Datadog configuration settings](#additional-configuration)
      - [Activate or reconfigure Datadog instrumentation](#integration-instrumentation)

#### Configuring OpenTelemetry

You can send OpenTelemetry traces directly to the Datadog agent (without `ddtrace`) by using OTLP. Check out our documentation on [OTLP ingest in the Datadog Agent](https://docs.datadoghq.com/tracing/setup_overview/open_standards/#otlp-ingest-in-datadog-agent) for details.

### Connect your application to the Datadog Agent

By default, `ddtrace` will connect to the agent using the first available settings in the listed priority:

1. Via any explicitly provided configuration settings (hostname/port/transport)
2. Via Unix Domain Socket (UDS) located at `/var/run/datadog/apm.socket`
3. Via HTTP over TCP to `127.0.0.1:8126`

If your Datadog Agent is listening at any of these locations, no further configuration should be required.

If your agent runs on a different host or container than your application, or you would like to send traces via a different protocol, you will need to configure your application accordingly.

  - [How to send trace data via HTTP over TCP to agent](#changing-default-agent-hostname-and-port)
  - [How to send trace data via Unix Domain Socket (UDS) to agent](#using-the-unix-domain-socket-uds-adapter)

### Final steps for installation

After setting up, your services will appear on the [APM services page](https://app.datadoghq.com/apm/services) within a few minutes. Learn more about [using the APM UI][visualization docs].

## Manual Instrumentation

If you aren't using a supported framework instrumentation, you may want to manually instrument your code.

To trace any Ruby code, you can use the `Datadog::Tracing.trace` method:

```ruby
Datadog::Tracing.trace(name, **options) do |span, trace|
  # Wrap this block around the code you want to instrument
  # Additionally, you can modify the span here.
  # e.g. Change the resource name, set tags, etc...
end
```

Where `name` should be a `String` that describes the generic kind of operation being done (e.g. `'web.request'`, or `'request.parse'`)

And `options` are the following optional keyword arguments:

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

Calling `Datadog::Tracing.trace` without a block will cause the function to return a `Datadog::Tracing::SpanOperation` that is started, but not finished. You can then modify this span however you wish, then close it `finish`.

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

Many popular libraries and frameworks are supported out-of-the-box, which can be auto-instrumented. Although they are not activated automatically, they can be easily activated and configured by using the `Datadog.configure` API:

```ruby
Datadog.configure do |c|
  # Activates and configures an integration
  c.tracing.instrument :integration_name, **options
end
```

`options` are keyword arguments for integration-specific configuration.

For a list of available integrations, and their configuration options, please refer to the following:

<!--
    Note: Please replicate any changes to this section also to
    https://github.com/datadog/documentation/blob/master/content/en/tracing/setup_overview/compatibility_requirements/ruby.md
    so that they remain in sync.
-->

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
| Dalli                      | `dalli`                    | `>= 2.0`                 | `>= 2.0`                  | *[Link](#dalli)*                    | *[Link](https://github.com/petergoldstein/dalli)*                              |
| DelayedJob                 | `delayed_job`              | `>= 4.1`                 | `>= 4.1`                  | *[Link](#delayedjob)*               | *[Link](https://github.com/collectiveidea/delayed_job)*                        |
| Elasticsearch              | `elasticsearch`            | `>= 1.0`                 | `>= 1.0`                  | *[Link](#elasticsearch)*            | *[Link](https://github.com/elastic/elasticsearch-ruby)*                        |
| Ethon                      | `ethon`                    | `>= 0.11`                | `>= 0.11`                 | *[Link](#ethon)*                    | *[Link](https://github.com/typhoeus/ethon)*                                    |
| Excon                      | `excon`                    | `>= 0.50`                | `>= 0.50`                 | *[Link](#excon)*                    | *[Link](https://github.com/excon/excon)*                                       |
| Faraday                    | `faraday`                  | `>= 0.14`                | `>= 0.14`                 | *[Link](#faraday)*                  | *[Link](https://github.com/lostisland/faraday)*                                |
| Grape                      | `grape`                    | `>= 1.0`                 | `>= 1.0`                  | *[Link](#grape)*                    | *[Link](https://github.com/ruby-grape/grape)*                                  |
| GraphQL                    | `graphql`                  | `>= 1.7.9`               | `>= 1.7.9`                | *[Link](#graphql)*                  | *[Link](https://github.com/rmosolgo/graphql-ruby)*                             |
| gRPC                       | `grpc`                     | `>= 1.7`                 | *gem not available*       | *[Link](#grpc)*                     | *[Link](https://github.com/grpc/grpc/tree/master/src/rubyc)*                   |
| hanami                     | `hanami`                   | `>= 1`, `< 2`            | `>= 1`, `< 2`             | *[Link](#hanami)*                   | *[Link](https://github.com/hanami/hanami)*                                     |
| http.rb                    | `httprb`                   | `>= 2.0`                 | `>= 2.0`                  | *[Link](#httprb)*                   | *[Link](https://github.com/httprb/http)*                                       |
| httpclient                 | `httpclient`               | `>= 2.2`                 | `>= 2.2`                  | *[Link](#httpclient)*               | *[Link](https://github.com/nahi/httpclient)*                                     |
| httpx                      | `httpx`                    | `>= 0.11`                | `>= 0.11`                 | *[Link](#httpx)*                    | *[Link](https://gitlab.com/honeyryderchuck/httpx)*                             |
| Kafka                      | `ruby-kafka`               | `>= 0.7.10`              | `>= 0.7.10`               | *[Link](#kafka)*                    | *[Link](https://github.com/zendesk/ruby-kafka)*                                |
| Makara (via Active Record) | `makara`                   | `>= 0.3.5`               | `>= 0.3.5`                | *[Link](#active-record)*            | *[Link](https://github.com/instacart/makara)*                                  |
| MongoDB                    | `mongo`                    | `>= 2.1`                 | `>= 2.1`                  | *[Link](#mongodb)*                  | *[Link](https://github.com/mongodb/mongo-ruby-driver)*                         |
| MySQL2                     | `mysql2`                   | `>= 0.3.21`              | *gem not available*       | *[Link](#mysql2)*                   | *[Link](https://github.com/brianmario/mysql2)*                                 |
| Net/HTTP                   | `http`                     | *(Any supported Ruby)*   | *(Any supported Ruby)*    | *[Link](#nethttp)*                  | *[Link](https://ruby-doc.org/stdlib-2.4.0/libdoc/net/http/rdoc/Net/HTTP.html)* |
| Postgres                     | `pg`                   | `>= 0.18.4`              | *gem not available*       | *[Link](#postgres)*                   | *[Link](https://github.com/ged/ruby-pg)*                  |
| Presto                     | `presto`                   | `>= 0.5.14`              | `>= 0.5.14`               | *[Link](#presto)*                   | *[Link](https://github.com/treasure-data/presto-client-ruby)*                  |
| Qless                      | `qless`                    | `>= 0.10.0`              | `>= 0.10.0`               | *[Link](#qless)*                    | *[Link](https://github.com/seomoz/qless)*                                      |
| Que                        | `que`                      | `>= 1.0.0.beta2`         | `>= 1.0.0.beta2`          | *[Link](#que)*                      | *[Link](https://github.com/que-rb/que)*                                        |
| Racecar                    | `racecar`                  | `>= 0.3.5`               | `>= 0.3.5`                | *[Link](#racecar)*                  | *[Link](https://github.com/zendesk/racecar)*                                   |
| Rack                       | `rack`                     | `>= 1.1`                 | `>= 1.1`                  | *[Link](#rack)*                     | *[Link](https://github.com/rack/rack)*                                         |
| Rails                      | `rails`                    | `>= 3.2`                 | `>= 3.2`                  | *[Link](#rails)*                    | *[Link](https://github.com/rails/rails)*                                       |
| Rake                       | `rake`                     | `>= 12.0`                | `>= 12.0`                 | *[Link](#rake)*                     | *[Link](https://github.com/ruby/rake)*                                         |
| Redis                      | `redis`                    | `>= 3.2`                 | `>= 3.2`                 | *[Link](#redis)*                    | *[Link](https://github.com/redis/redis-rb)*                                    |
| Resque                     | `resque`                   | `>= 1.0`                 | `>= 1.0`                  | *[Link](#resque)*                   | *[Link](https://github.com/resque/resque)*                                     |
| Rest Client                | `rest-client`              | `>= 1.8`                 | `>= 1.8`                  | *[Link](#rest-client)*              | *[Link](https://github.com/rest-client/rest-client)*                           |
| Sequel                     | `sequel`                   | `>= 3.41`                | `>= 3.41`                 | *[Link](#sequel)*                   | *[Link](https://github.com/jeremyevans/sequel)*                                |
| Shoryuken                  | `shoryuken`                | `>= 3.2`                 | `>= 3.2`                  | *[Link](#shoryuken)*                | *[Link](https://github.com/phstc/shoryuken)*                                   |
| Sidekiq                    | `sidekiq`                  | `>= 3.5.4`               | `>= 3.5.4`                | *[Link](#sidekiq)*                  | *[Link](https://github.com/mperham/sidekiq)*                                   |
| Sinatra                    | `sinatra`                  | `>= 1.4`                 | `>= 1.4`                  | *[Link](#sinatra)*                  | *[Link](https://github.com/sinatra/sinatra)*                                   |
| Sneakers                   | `sneakers`                 | `>= 2.12.0`              | `>= 2.12.0`               | *[Link](#sneakers)*                 | *[Link](https://github.com/jondot/sneakers)*                                   |
| Stripe                     | `stripe`                   | `>= 5.15.0`              | `>= 5.15.0`               | *[Link](#stripe)*                   | *[Link](https://github.com/stripe/stripe-ruby)*                                |
| Sucker Punch               | `sucker_punch`             | `>= 2.0`                 | `>= 2.0`                  | *[Link](#sucker-punch)*             | *[Link](https://github.com/brandonhilkert/sucker_punch)*                       |

#### CI Visibility

For Datadog CI Visibility, library instrumentation can be activated and configured by using the following `Datadog.configure` API:

```ruby
Datadog.configure do |c|
  # Activates and configures an integration
  c.ci.instrument :integration_name, **options
end
```

`options` are keyword arguments for integration-specific configuration.

These are the available CI Visibility integrations:

| Name      | Key        | Versions Supported: MRI | Versions Supported: JRuby | How to configure    | Gem source                                          |
|-----------|------------|-------------------------|---------------------------|---------------------|-----------------------------------------------------|
| Cucumber  | `cucumber` | `>= 3.0`                | `>= 1.7.16`               | *[Link](#cucumber)* | *[Link](https://github.com/cucumber/cucumber-ruby)* |
| RSpec     | `rspec`    | `>= 3.0.0`              | `>= 3.0.0`                | *[Link](#rspec)*    | *[Link](https://github.com/rspec/rspec)*            |

### Action Cable

The Action Cable integration traces broadcast messages and channel actions.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :action_cable
end
```

### Action Mailer

The Action Mailer integration provides tracing for Rails 5 ActionMailer actions.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'
Datadog.configure do |c|
  c.tracing.instrument :action_mailer, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `email_data` | Whether or not to append additional email payload metadata to `action_mailer.deliver` spans. Fields include `['subject', 'to', 'from', 'bcc', 'cc', 'date', 'perform_deliveries']`. | `false` |

### Action Pack

Most of the time, Action Pack is set up as part of Rails, but it can be activated separately:

```ruby
require 'actionpack'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :action_pack
end
```

### Action View

Most of the time, Action View is set up as part of Rails, but it can be activated separately:

```ruby
require 'actionview'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :action_view, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| ---| --- | --- |
| `template_base_path` | Used when the template name is parsed. If you don't store your templates in the `views/` folder, you may need to change this value | `'views/'` |

### Active Job

Most of the time, Active Job is set up as part of Rails, but it can be activated separately:

```ruby
require 'active_job'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :active_job
end

ExampleJob.perform_later
```

### Active Model Serializers

The Active Model Serializers integration traces the `serialize` event for version 0.9+ and the `render` event for version 0.10+.

```ruby
require 'active_model_serializers'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :active_model_serializers
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

Datadog.configure do |c|
  c.tracing.instrument :active_record, **options
end

Dir::Tmpname.create(['test', '.sqlite']) do |db|
  conn = ActiveRecord::Base.establish_connection(adapter: 'sqlite3',
                                                 database: db)
  conn.connection.execute('SELECT 42') # traced!
end
```

`options` are the following keyword arguments:

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

Datadog.configure do |c|
  # Symbol matching your database connection in config/database.yml
  # Only available if you are using Rails with ActiveRecord.
  c.tracing.instrument :active_record, describes: :secondary_database, service_name: 'secondary-db'

  # Block configuration pattern.
  c.tracing.instrument :active_record, describes: :secondary_database do |second_db|
    second_db.service_name = 'secondary-db'
  end

  # Connection string with the following connection settings:
  # adapter, username, host, port, database
  # Other fields are ignored.
  c.tracing.instrument :active_record, describes: 'mysql2://root@127.0.0.1:3306/mysql', service_name: 'secondary-db'

  # Hash with following connection settings:
  # adapter, username, host, port, database
  # Other fields are ignored.
  c.tracing.instrument :active_record, describes: {
      adapter:  'mysql2',
      host:     '127.0.0.1',
      port:     '3306',
      database: 'mysql',
      username: 'root'
    },
    service_name: 'secondary-db'

  # If using the `makara` gem, it's possible to match on connection `role`:
  c.tracing.instrument :active_record, describes: { makara_role: 'primary' }, service_name: 'primary-db'
  c.tracing.instrument :active_record, describes: { makara_role: 'replica' }, service_name: 'secondary-db'
end
```

You can also create configurations based on partial matching of database connection fields:

```ruby
Datadog.configure do |c|
  # Matches any connection on host `127.0.0.1`.
  c.tracing.instrument :active_record, describes: { host:  '127.0.0.1' }, service_name: 'local-db'

  # Matches any `mysql2` connection.
  c.tracing.instrument :active_record, describes: { adapter: 'mysql2'}, service_name: 'mysql-db'

  # Matches any `mysql2` connection to the `reports` database.
  #
  # In case of multiple matching `describe` configurations, the latest one applies.
  # In this case a connection with both adapter `mysql` and database `reports`
  # will be configured `service_name: 'reports-db'`, not `service_name: 'mysql-db'`.
  c.tracing.instrument :active_record, describes: { adapter: 'mysql2', database:  'reports'}, service_name: 'reports-db'
end
```

When multiple `describes` configurations match a connection, the latest configured rule that matches will be applied.

If ActiveRecord traces an event that uses a connection that matches a key defined by `describes`, it will use the trace settings assigned to that connection. If the connection does not match any of the described connections, it will use default settings defined by `c.tracing.instrument :active_record` instead.

### Active Support

Most of the time, Active Support is set up as part of Rails, but it can be activated separately:

```ruby
require 'activesupport'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :active_support, **options
end

cache = ActiveSupport::Cache::MemoryStore.new
cache.read('city')
```

`options` are the following keyword arguments:

| Key | Description | Default |
| ---| --- | --- |
| `cache_service` | Service name used for caching with `active_support` instrumentation. | `active_support-cache` |

### AWS

The AWS integration will trace every interaction (e.g. API calls) with AWS services (S3, ElastiCache etc.).

```ruby
require 'aws-sdk'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :aws, **options
end

# Perform traced call
Aws::S3::Client.new.list_buckets
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `aws` instrumentation | `'aws'` |

### Concurrent Ruby

The Concurrent Ruby integration adds support for context propagation when using `::Concurrent::Future`.
Making sure that code traced within the `Future#execute` will have correct parent set.

To activate your integration, use the `Datadog.configure` method:

```ruby
# Inside Rails initializer or equivalent
Datadog.configure do |c|
  # Patches ::Concurrent::Future to use ExecutorService that propagates context
  c.tracing.instrument :concurrent_ruby
end

# Pass context into code executed within Concurrent::Future
Datadog::Tracing.trace('outer') do
  Concurrent::Future.execute { Datadog::Tracing.trace('inner') { } }.wait
end
```

### Cucumber

Cucumber integration will trace all executions of scenarios and steps when using `cucumber` framework.

To activate your integration, use the `Datadog.configure` method:

```ruby
require 'cucumber'
require 'ddtrace'

# Configure default Cucumber integration
Datadog.configure do |c|
  c.ci.instrument :cucumber, **options
end

# Example of how to attach tags from scenario to active span
Around do |scenario, block|
  active_span = Datadog.configuration[:cucumber][:tracer].active_span
  unless active_span.nil?
    scenario.tags.filter { |tag| tag.include? ':' }.each do |tag|
      active_span.set_tag(*tag.name.split(':', 2))
    end
  end
  block.call
end
```

`options` are the following keyword arguments:

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
Datadog.configure do |c|
  c.tracing.instrument :dalli, **options
end

# Configure Dalli tracing behavior for single client
client = Dalli::Client.new('localhost:11211', **options)
client.set('abc', 123)
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `dalli` instrumentation | `'memcached'` |

### DelayedJob

The DelayedJob integration uses lifecycle hooks to trace the job executions and enqueues.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :delayed_job, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Elasticsearch

The Elasticsearch integration will trace any call to `perform_request` in the `Client` object:

```ruby
require 'elasticsearch/transport'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :elasticsearch, **options
end

# Perform a query to Elasticsearch
client = Elasticsearch::Client.new url: 'http://127.0.0.1:9200'
response = client.perform_request 'GET', '_cluster/health'

# In case you want to override the global configuration for a certain client instance
Datadog.configure_onto(client.transport, **options)
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `quantize` | Hash containing options for quantization. May include `:show` with an Array of keys to not quantize (or `:all` to skip quantization), or `:exclude` with Array of keys to exclude entirely. | `{}` |
| `service_name` | Service name used for `elasticsearch` instrumentation | `'elasticsearch'` |

### Ethon

The `ethon` integration will trace any HTTP request through `Easy` or `Multi` objects. Note that this integration also supports `Typhoeus` library which is based on `Ethon`.

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :ethon, **options

  # optionally, specify a different service name for hostnames matching a regex
  c.tracing.instrument :ethon, describes: /user-[^.]+\.example\.com/ do |ethon|
    ethon.service_name = 'user.example.com'
    ethon.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end
```

`options` are the following keyword arguments:

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
Datadog.configure do |c|
  c.tracing.instrument :excon, **options

  # optionally, specify a different service name for hostnames matching a regex
  c.tracing.instrument :excon, describes: /user-[^.]+\.example\.com/ do |excon|
    excon.service_name = 'user.example.com'
    excon.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end

connection = Excon.new('https://example.com')
connection.get
```

`options` are the following keyword arguments:

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
Datadog.configure do |c|
  c.tracing.instrument :faraday, **options

  # optionally, specify a different service name for hostnames matching a regex
  c.tracing.instrument :faraday, describes: /user-[^.]+\.example\.com/ do |faraday|
    faraday.service_name = 'user.example.com'
    faraday.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end

# In case you want to override the global configuration for a certain client instance
connection = Faraday.new('https://example.com') do |builder|
  builder.use(:ddtrace, **options)
  builder.adapter Faraday.default_adapter
end

connection.get('/foo')
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `error_handler` | A `Proc` that accepts a `response` parameter. If it evaluates to a *truthy* value, the trace span is marked as an error. By default only sets 5XX responses as errors. | `nil` |
| `service_name` | Service name for Faraday instrumentation. When provided to middleware for a specific connection, it applies only to that connection object. | `'faraday'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |

### Grape

The Grape integration adds the instrumentation to Grape endpoints and filters. This integration can work side by side with other integrations like Rack and Rails.

To activate your integration, use the `Datadog.configure` method before defining your Grape application:

```ruby
# api.rb
require 'grape'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :grape, **options
end

# Then define your application
class RackTestingAPI < Grape::API
  desc 'main endpoint'
  get :success do
    'Hello world!'
  end
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Grape should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `error_statuses`| Defines a status code or range of status codes which should be marked as errors. `'404,405,500-599'` or `[404,405,'500-599']` | `nil` |

### GraphQL

The GraphQL integration activates instrumentation for GraphQL queries.

To activate your integration, use the `Datadog.configure` method:

```ruby
# Inside Rails initializer or equivalent
Datadog.configure do |c|
  c.tracing.instrument :graphql, schemas: [YourSchema], **options
end

# Then run a GraphQL query
YourSchema.execute(query, variables: {}, context: {}, operation_name: nil)
```

The `instrument :graphql` method accepts the following parameters. Additional options can be substituted in for `options`:

| Key | Description | Default |
| --- | ----------- | ------- |
| `schemas` | Required. Array of `GraphQL::Schema` objects which to trace. Tracing will be added to all the schemas listed, using the options provided to this configuration. If you do not provide any, then tracing will not be activated. | `[]` |
| `service_name` | Service name used for graphql instrumentation | `'ruby-graphql'` |

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

Do *NOT* `instrument :graphql` in `Datadog.configure` if you choose to configure manually, as to avoid double tracing. These two means of configuring GraphQL tracing are considered mutually exclusive.

### gRPC

The `grpc` integration adds both client and server interceptors, which run as middleware before executing the service's remote procedure call. As gRPC applications are often distributed, the integration shares trace information between client and server.

To setup your integration, use the `Datadog.configure` method like so:

```ruby
require 'grpc'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :grpc, **options
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

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
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

### hanami

The `hanami` integration will instrument routing, action and render for your hanami application. To enable the `hanami` instrumentation, it is recommended to auto instrument with

```
gem 'ddtrace', require: 'ddtrace/auto_instrument'
```

and create an initializer file in your `config/initializers` folder:

```ruby
# config/initializers/datadog.rb
Datadog.configure do |c|
  c.tracing.instrument :hanami, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name for `hanami` instrumentation. | `nil` |

### http.rb

The http.rb integration will trace any HTTP call using the Http.rb gem.

```ruby
require 'http'
require 'ddtrace'
Datadog.configure do |c|
  c.tracing.instrument :httprb, **options
  # optionally, specify a different service name for hostnames matching a regex
  c.tracing.instrument :httprb, describes: /user-[^.]+\.example\.com/ do |httprb|
    httprb.service_name = 'user.example.com'
    httprb.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `service_name` | Service name for `httprb` instrumentation. | `'httprb'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |
| `error_status_codes` | Range or Array of HTTP status codes that should be traced as errors. | `400...600` |

### httpclient

The httpclient integration will trace any HTTP call using the httpclient gem.

```ruby
require 'httpclient'
require 'ddtrace'
Datadog.configure do |c|
  c.tracing.instrument :httpclient, **options
  # optionally, specify a different service name for hostnames matching a regex
  c.tracing.instrument :httpclient, describes: /user-[^.]+\.example\.com/ do |httpclient|
    httpclient.service_name = 'user.example.com'
    httpclient.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `service_name` | Service name for `httpclient` instrumentation. | `'httpclient'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |
| `error_status_codes` | Range or Array of HTTP status codes that should be traced as errors. | `400...600` |

### httpx

`httpx` maintains its [own integration with `ddtrace`](https://honeyryderchuck.gitlab.io/httpx/wiki/Datadog-Adapter):

```ruby
require "ddtrace"
require "httpx/adapters/datadog"

Datadog.configure do |c|
  c.tracing.instrument :httpx

  # optionally, specify a different service name for hostnames matching a regex
  c.tracing.instrument :httpx, describes: /user-[^.]+\.example\.com/ do |http|
    http.service_name = 'user.example.com'
    http.split_by_domain = false # Only necessary if split_by_domain is true by default
  end
end
```

### Kafka

The Kafka integration provides tracing of the `ruby-kafka` gem:

You can enable it through `Datadog.configure`:

```ruby
require 'active_support/notifications' # required to enable 'ruby-kafka' instrumentation
require 'kafka'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :kafka
end
```

### MongoDB

The integration traces any `Command` that is sent from the [MongoDB Ruby Driver](https://github.com/mongodb/mongo-ruby-driver) to a MongoDB cluster. By extension, Object Document Mappers (ODM) such as Mongoid are automatically instrumented if they use the official Ruby driver. To activate the integration, simply:

```ruby
require 'mongo'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :mongo, **options
end

# Create a MongoDB client and use it as usual
client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'artists')
collection = client[:people]
collection.insert_one({ name: 'Steve' })

# In case you want to override the global configuration for a certain client instance
Datadog.configure_onto(client, **options)
```

`options` are the following keyword arguments:

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

Datadog.configure do |c|
  # Network connection string
  c.tracing.instrument :mongo, describes: '127.0.0.1:27017', service_name: 'mongo-primary'

  # Network connection regular expression
  c.tracing.instrument :mongo, describes: /localhost.*/, service_name: 'mongo-secondary'
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

Datadog.configure do |c|
  c.tracing.instrument :mysql2, **options
end

client = Mysql2::Client.new(:host => "localhost", :username => "root")
client.query("SELECT * FROM users WHERE group='x'")
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `mysql2` instrumentation | `'mysql2'` |
| `comment_propagation` | SQL comment propagation mode  for database monitoring. <br />(example: `disabled` \| `service`\| `full`). <br /><br />**Important**: *Note that enabling sql comment propagation results in potentially confidential data (service names) being stored in the databases which can then be accessed by other 3rd parties that have been granted access to the database.* | `'disabled'` |

### Net/HTTP

The Net/HTTP integration will trace any HTTP call using the standard lib Net::HTTP module.

```ruby
require 'net/http'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :http, **options

  # optionally, specify a different service name for hostnames matching a regex
  c.tracing.instrument :http, describes: /user-[^.]+\.example\.com/ do |http|
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

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `service_name` | Service name used for `http` instrumentation | `'net/http'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |
| `error_status_codes` | Range or Array of HTTP status codes that should be traced as errors. | `400...600` |

If you wish to configure each connection object individually, you may use the `Datadog.configure_onto` as it follows:

```ruby
client = Net::HTTP.new(host, port)
Datadog.configure_onto(client, **options)
```
### Postgres

The PG integration traces SQL commands sent through the `pg` gem via:
* `exec`, `exec_params`, `exec_prepared`;
* `async_exec`, `async_exec_params`, `async_exec_prepared`; or,
* `sync_exec`, `sync_exec_params`, `sync_exec_prepared`

```ruby
require 'pg'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :pg, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `pg` instrumentation | `'pg'` |
| `comment_propagation` | SQL comment propagation mode  for database monitoring. <br />(example: `disabled` \| `service`\| `full`). <br /><br />**Important**: *Note that enabling sql comment propagation results in potentially confidential data (service names) being stored in the databases which can then be accessed by other 3rd parties that have been granted access to the database.* | `'disabled'` |

### Presto

The Presto integration traces any SQL command sent through `presto-client` gem.

```ruby
require 'presto-client'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :presto, **options
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

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `presto` instrumentation | `'presto'` |

### Qless

The Qless integration uses lifecycle hooks to trace job executions.

To add tracing to a Qless job:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :qless, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `tag_job_data` | Enable tagging with job arguments. true for on, false for off. | `false` |
| `tag_job_tags` | Enable tagging with job tags. true for on, false for off. | `false` |

### Que

The Que integration is a middleware which will trace job executions.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :que, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Que should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `tag_args` | Enable tagging of a job's args field. `true` for on, `false` for off. | `false` |
| `tag_data` | Enable tagging of a job's data field. `true` for on, `false` for off. | `false` |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Racecar

The Racecar integration provides tracing for Racecar jobs.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :racecar, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `racecar` instrumentation | `'racecar'` |

### Rack

The Rack integration provides a middleware that traces all requests before they reach the underlying framework or application. It responds to the Rack minimal interface, providing reasonable values that can be retrieved at the Rack level.

This integration is automatically activated with web frameworks like Rails. If you're using a plain Rack application, enable the integration it to your `config.ru`:

```ruby
# config.ru example
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :rack, **options
end

use Datadog::Tracing::Contrib::Rack::TraceMiddleware

app = proc do |env|
  [ 200, {'Content-Type' => 'text/plain'}, ['OK'] ]
end

run app
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `application` | Your Rack application. Required for `middleware_names`. | `nil` |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) so that this service trace is connected with a trace of another service if tracing headers are received | `true` |
| `headers` | Hash of HTTP request or response headers to add as tags to the `rack.request`. Accepts `request` and `response` keys with Array values e.g. `['Last-Modified']`. Adds `http.request.headers.*` and `http.response.headers.*` tags respectively. | `{ response: ['Content-Type', 'X-Request-ID'] }` |
| `middleware_names` | Enable this if you want to use the last executed middleware class as the resource name for the `rack` span. If enabled alongside the `rails` instrumention, `rails` takes precedence by setting the `rack` resource name to the active `rails` controller when applicable. Requires `application` option to use. | `false` |
| `quantize` | Hash containing options for quantization. May include `:query` or `:fragment`. | `{}` |
| `quantize.base` | Defines behavior for URL base (scheme, host, port). May be `:show` to keep URL base in `http.url` tag and not set `http.base_url` tag, or `nil` to remove URL base from `http.url` tag by default, leaving a path and setting `http.base_url`. Option must be nested inside the `quantize` option. | `nil` |
| `quantize.query` | Hash containing options for query portion of URL quantization. May include `:show` or `:exclude`. See options below. Option must be nested inside the `quantize` option. | `{}` |
| `quantize.query.show` | Defines which values should always be shown. May be an Array of strings, `:all` to show all values, or `nil` to show no values. Option must be nested inside the `query` option. | `nil` |
| `quantize.query.exclude` | Defines which values should be removed entirely. May be an Array of strings, `:all` to remove the query string entirely, or `nil` to exclude nothing. Option must be nested inside the `query` option. | `nil` |
| `quantize.query.obfuscate` | Defines query string redaction behaviour. May be a hash of options, `:internal` to use the default internal obfuscation settings, or `nil` to disable obfuscation. Note that obfuscation is a string-wise operation, not a key-value operation. When enabled, `query.show` defaults to `:all` if otherwise unset. Option must be nested inside the `query` option. | `nil` |
| `quantize.query.obfuscate.with` | Defines the string to replace obfuscated matches with. May be a String. Option must be nested inside the `query.obfuscate` option. | `'<redacted>'` |
| `quantize.query.obfuscate.regex` | Defines the regex with which the query string will be redacted. May be a Regexp, or `:internal` to use the default internal Regexp, which redacts well-known sensitive data. Each match is redacted entirely by replacing it with `query.obfuscate.with`. Option must be nested inside the `query.obfuscate` option. | `:internal` |
| `quantize.fragment` | Defines behavior for URL fragments. May be `:show` to show URL fragments, or `nil` to remove fragments. Option must be nested inside the `quantize` option. | `nil` |
| `request_queuing` | Track HTTP request time spent in the queue of the frontend server. See [HTTP request queuing](#http-request-queuing) for setup details. | `false` |
| `web_service_name` | Service name for frontend server request queuing spans. (e.g. `'nginx'`) | `'web-server'` |

Deprecation notice:
- `quantize.base` will change its default from `:exclude` to `:show` in a future version. Voluntarily moving to `:show` is recommended.
- `quantize.query.show` will change its default to `:all` in a future version, together with `quantize.query.obfuscate` changing to `:internal`. Voluntarily moving to these future values is recommended.

**Configuring URL quantization behavior**

```ruby
Datadog.configure do |c|
  # Default behavior: all values are quantized, base is removed, fragment is removed.
  # http://example.com/path?category_id=1&sort_by=asc#featured --> /path?category_id&sort_by
  # http://example.com:8080/path?categories[]=1&categories[]=2 --> /path?categories[]

  # Remove URL base (scheme, host, port)
  # http://example.com/path?category_id=1&sort_by=asc#featured --> /path?category_id&sort_by#featured
  c.tracing.instrument :rack, quantize: { base: :exclude }

  # Show URL base
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id&sort_by#featured
  c.tracing.instrument :rack, quantize: { base: :show }

  # Show values for any query string parameter matching 'category_id' exactly
  # http://example.com/path?category_id=1&sort_by=asc#featured --> /path?category_id=1&sort_by
  c.tracing.instrument :rack, quantize: { query: { show: ['category_id'] } }

  # Show all values for all query string parameters
  # http://example.com/path?category_id=1&sort_by=asc#featured --> /path?category_id=1&sort_by=asc
  c.tracing.instrument :rack, quantize: { query: { show: :all } }

  # Totally exclude any query string parameter matching 'sort_by' exactly
  # http://example.com/path?category_id=1&sort_by=asc#featured --> /path?category_id
  c.tracing.instrument :rack, quantize: { query: { exclude: ['sort_by'] } }

  # Remove the query string entirely
  # http://example.com/path?category_id=1&sort_by=asc#featured --> /path
  c.tracing.instrument :rack, quantize: { query: { exclude: :all } }

  # Show URL fragments
  # http://example.com/path?category_id=1&sort_by=asc#featured --> /path?category_id&sort_by#featured
  c.tracing.instrument :rack, quantize: { fragment: :show }

  # Obfuscate query string, defaulting to showing all values
  # http://example.com/path?password=qwerty&sort_by=asc#featured --> /path?<redacted>&sort_by=asc
  c.tracing.instrument :rack, quantize: { query: { obfuscate: {} } }

  # Obfuscate query string using the provided regex, defaulting to showing all values
  # http://example.com/path?category_id=1&sort_by=asc#featured --> /path?<redacted>&sort_by=asc
  c.tracing.instrument :rack, quantize: { query: { obfuscate: { regex: /category_id=\d+/ } } }

  # Obfuscate query string using a custom redaction string
  # http://example.com/path?password=qwerty&sort_by=asc#featured --> /path?REMOVED&sort_by=asc
  c.tracing.instrument :rack, quantize: { query: { obfuscate: { with: 'REMOVED' } } }
end
```

### Rails

The Rails integration will trace requests, database calls, templates rendering, and cache read/write/delete operations. The integration makes use of the Active Support Instrumentation, listening to the Notification API so that any operation instrumented by the API is traced.

To enable the Rails instrumentation, create an initializer file in your `config/initializers` folder:

```ruby
# config/initializers/datadog.rb
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :rails, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) so that this service trace is connected with a trace of another service if tracing headers are received | `true` |
| `request_queuing` | Track HTTP request time spent in the queue of the frontend server. See [HTTP request queuing](#http-request-queuing) for setup details. | `false` |
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

You can add instrumentation around your Rake tasks by activating the `rake` integration and
providing a list of what Rake tasks need to be instrumented.

**Avoid instrumenting long-running Rake tasks, as such tasks can aggregate large traces in
memory that are never flushed until the task finishes.**

For long-running tasks, use [Manual instrumentation](#manual-instrumentation) around recurring code paths.

To activate Rake task tracing, add the following to your `Rakefile`:

```ruby
# At the top of your Rakefile:
require 'rake'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :rake, tasks: ['my_task'], **options
end

task :my_task do
  # Do something task work here...
end

Rake::Task['my_task'].invoke
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Rake tasks should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `quantize` | Hash containing options for quantization of task arguments. See below for more details and examples. | `{}` |
| `service_name` | Service name used for `rake` instrumentation | `'rake'` |
| `tasks` | Names of the Rake tasks to instrument | `[]` |

**Configuring task quantization behavior**

```ruby
Datadog.configure do |c|
  # Given a task that accepts :one, :two, :three...
  # Invoked with 'foo', 'bar', 'baz'.

  # Default behavior: all arguments are quantized.
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> { one: '?', two: '?', three: '?' }
  c.tracing.instrument :rake

  # Show values for any argument matching :two exactly
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> { one: '?', two: 'bar', three: '?' }
  c.tracing.instrument :rake, quantize: { args: { show: [:two] } }

  # Show all values for all arguments.
  # `rake.invoke.args` tag  --> ['foo', 'bar', 'baz']
  # `rake.execute.args` tag --> { one: 'foo', two: 'bar', three: 'baz' }
  c.tracing.instrument :rake, quantize: { args: { show: :all } }

  # Totally exclude any argument matching :three exactly
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> { one: '?', two: '?' }
  c.tracing.instrument :rake, quantize: { args: { exclude: [:three] } }

  # Remove the arguments entirely
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> {}
  c.tracing.instrument :rake, quantize: { args: { exclude: :all } }
end
```

### Redis

The Redis integration will trace simple calls as well as pipelines.

```ruby
require 'redis'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :redis, **options
end

# Perform Redis commands
redis = Redis.new
redis.set 'foo', 'bar'
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `service_name` | Service name used for `redis` instrumentation | `'redis'` |
| `command_args` | Show the command arguments (e.g. `key` in `GET key`) as resource name and tag | true |

**Configuring trace settings per instance**

With Redis version >= 5:

```ruby
require 'redis'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :redis # Enabling integration instrumentation is still required
end

customer_cache = Redis.new(custom: { datadog: { service_name: 'custom-cache' } })
invoice_cache = Redis.new(custom: { datadog: { service_name: 'invoice-cache' } })

# Traced call will belong to `customer-cache` service
customer_cache.get(...)
# Traced call will belong to `invoice-cache` service
invoice_cache.get(...)
```

With Redis version < 5:

```ruby
require 'redis'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :redis # Enabling integration instrumentation is still required
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

Datadog.configure do |c|
  # The default configuration for any redis client
  c.tracing.instrument :redis, service_name: 'redis-default'

  # The configuration matching a given unix socket.
  c.tracing.instrument :redis, describes: { url: 'unix://path/to/file' }, service_name: 'redis-unix'

  # For network connections, only these fields are considered during matching:
  # scheme, host, port, db
  # Other fields are ignored.

  # Network connection string
  c.tracing.instrument :redis, describes: 'redis://127.0.0.1:6379/0', service_name: 'redis-connection-string'
  c.tracing.instrument :redis, describes: { url: 'redis://127.0.0.1:6379/1' }, service_name: 'redis-connection-url'
  # Network client hash
  c.tracing.instrument :redis, describes: { host: 'my-host.com', port: 6379, db: 1, scheme: 'redis' }, service_name: 'redis-connection-hash'
  # Only a subset of the connection hash
  c.tracing.instrument :redis, describes: { host: ENV['APP_CACHE_HOST'], port: ENV['APP_CACHE_PORT'] }, service_name: 'redis-cache'
  c.tracing.instrument :redis, describes: { host: ENV['SIDEKIQ_CACHE_HOST'] }, service_name: 'redis-sidekiq'
end
```

When multiple `describes` configurations match a connection, the latest configured rule that matches will be applied.

### Resque

The Resque integration uses Resque hooks that wraps the `perform` method.

To add tracing to a Resque job:

```ruby
require 'resque'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :resque, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Rest Client

The `rest-client` integration is available through the `ddtrace` middleware:

```ruby
require 'rest_client'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :rest_client, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `true` |
| `service_name` | Service name for `rest_client` instrumentation. | `'rest_client'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |

### RSpec

RSpec integration will trace all executions of example groups and examples when using `rspec` test framework.

To activate your integration, use the `Datadog.configure` method:

```ruby
require 'rspec'
require 'ddtrace'

# Configure default RSpec integration
Datadog.configure do |c|
  c.ci.instrument :rspec, **options
end
```

`options` are the following keyword arguments:

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

Datadog.configure do |c|
  c.tracing.instrument :sequel, **options
end

# Perform a query
articles = database[:articles]
articles.all
```

`options` are the following keyword arguments:

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

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :shoryuken, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `tag_body` | Tag spans with the SQS message body `true` or `false` | `false` |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Sidekiq

The Sidekiq integration is a client-side & server-side middleware which will trace job queuing and executions respectively.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :sidekiq, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `tag_args` | Enable tagging of job arguments. `true` for on, `false` for off. | `false` |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { \|span, error\| span.set_error(error) unless span.nil? }` |
| `quantize` | Hash containing options for quantization of job arguments. | `{}` |

### Sinatra

The Sinatra integration traces requests and template rendering.

To start using the tracing client, make sure you import `ddtrace` and `instrument :sinatra` after either `sinatra` or `sinatra/base`, and before you define your application/routes:

#### Classic application

```ruby
require 'sinatra'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :sinatra, **options
end

get '/' do
  'Hello world!'
end
```

#### Modular application

```ruby
require 'sinatra/base'
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :sinatra, **options
end

class NestedApp < Sinatra::Base
  get '/nested' do
    'Hello from nested app!'
  end
end

class App < Sinatra::Base
  use NestedApp

  get '/' do
    'Hello world!'
  end
end
```

#### Instrumentation options

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) so that this service trace is connected with a trace of another service if tracing headers are received | `true` |
| `headers` | Hash of HTTP request or response headers to add as tags to the `sinatra.request`. Accepts `request` and `response` keys with Array values e.g. `['Last-Modified']`. Adds `http.request.headers.*` and `http.response.headers.*` tags respectively. | `{ response: ['Content-Type', 'X-Request-ID'] }` |
| `resource_script_names` | Prepend resource names with script name | `false` |

### Sneakers

The Sneakers integration is a server-side middleware which will trace job executions.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :sneakers, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Sneakers should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `tag_body` | Enable tagging of job message. `true` for on, `false` for off. | `false` |
| `error_handler` | Custom error handler invoked when a job raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. Useful for ignoring transient errors. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

### Stripe

The Stripe integration traces Stripe API requests.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :stripe, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Stripe should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |

### Sucker Punch

The `sucker_punch` integration traces all scheduled jobs:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :sucker_punch
end

# Execution of this job is traced
LogJob.perform_async('login')
```

## Additional configuration

To change the default behavior of Datadog tracing, you can set environment variables, or provide custom options inside a `Datadog.configure` block, e.g.:

```ruby
Datadog.configure do |c|
  c.service = 'billing-api'
  c.env = ENV['RACK_ENV']

  c.tracing.report_hostname = true
  c.tracing.test_mode.enabled = (ENV['RACK_ENV'] == 'test')
end
```

**Available configuration options:**

| Setting                                                 | Env Var                        | Default                                                           | Description                                                                                                                                                                                                                               |
|---------------------------------------------------------|--------------------------------|-------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Global**                                              |                                |                                                                   |                                                                                                                                                                                                                                           |
| `agent.host`                                            | `DD_AGENT_HOST`                | `127.0.0.1`                                                       | Hostname of agent to where trace data will be sent.                                                                                                                                                                                       |
| `agent.port`                                            | `DD_TRACE_AGENT_PORT`          | `8126`                                                            | Port of agent host to where trace data will be sent. If the [Agent configuration](#configuring-trace-data-ingestion) sets `receiver_port` or `DD_APM_RECEIVER_PORT` to something other than the default `8126`, then `DD_TRACE_AGENT_PORT` or `DD_TRACE_AGENT_URL` must match it.         |
|                                                         | `DD_TRACE_AGENT_URL`           | `nil`                                                             | Sets the URL endpoint where traces are sent. Has priority over `agent.host` and `agent.port`. If the [Agent configuration](#configuring-trace-data-ingestion) sets `receiver_port` or `DD_APM_RECEIVER_PORT` to something other than the default `8126`, then `DD_TRACE_AGENT_PORT` or `DD_TRACE_AGENT_URL` must match it.                |
| `diagnostics.debug`                                     | `DD_TRACE_DEBUG`               | `false`                                                           | Enables or disables debug mode. Prints verbose logs. **NOT recommended for production or other sensitive environments.** See [Debugging and diagnostics](#debugging-and-diagnostics) for more details.                                    |
| `diagnostics.startup_logs.enabled`                      | `DD_TRACE_STARTUP_LOGS`        | `nil`                                                             | Prints startup configuration and diagnostics to log. For assessing state of tracing at application startup. See [Debugging and diagnostics](#debugging-and-diagnostics) for more details.                                                 |
| `env`                                                   | `DD_ENV`                       | `nil`                                                             | Your application environment. (e.g. `production`, `staging`, etc.) This value is set as a tag on all traces.                                                                                                                              |
| `service`                                               | `DD_SERVICE`                   | *Ruby filename*                                                   | Your application's default service name. (e.g. `billing-api`) This value is set as a tag on all traces.                                                                                                                                   |
| `tags`                                                  | `DD_TAGS`                      | `nil`                                                             | Custom tags in value pairs separated by `,` (e.g. `layer:api,team:intake`) These tags are set on all traces. See [Environment and tags](#environment-and-tags) for more details.                                                          |
| `time_now_provider`                                     |                                | `->{ Time.now }`                                                  | Changes how time is retrieved. See [Setting the time provider](#Setting the time provider) for more details.                                                                                                                              |
| `version`                                               | `DD_VERSION`                   | `nil`                                                             | Your application version (e.g. `2.5`, `202003181415`, `1.3-alpha`, etc.) This value is set as a tag on all traces.                                                                                                                        |
| `telemetry.enabled`                                     | `DD_INSTRUMENTATION_TELEMETRY_ENABLED` | `false`                                                             | Allows you to enable sending telemetry data to Datadog. In a future release, we will be setting this to  `true` by default, as documented [here](https://docs.datadoghq.com/tracing/configure_data_security/#telemetry-collection).                                                                                                                                                                                          |
| **Tracing**                                             |                                |                                                                   |                                                                                                                                                                                                                                           |
| `tracing.analytics.enabled`                             | `DD_TRACE_ANALYTICS_ENABLED`   | `nil`                                                             | Enables or disables trace analytics. See [Sampling](#sampling) for more details.                                                                                                                                                          |
| `tracing.distributed_tracing.propagation_extract_style` | `DD_TRACE_PROPAGATION_STYLE_EXTRACT` | `['Datadog','b3multi','b3']` | Distributed tracing propagation formats to extract. Overrides `DD_TRACE_PROPAGATION_STYLE`. See [Distributed Tracing](#distributed-tracing) for more details.                                                                             |
| `tracing.distributed_tracing.propagation_inject_style`  | `DD_TRACE_PROPAGATION_STYLE_INJECT`  | `['Datadog']`                                                     | Distributed tracing propagation formats to inject. Overrides `DD_TRACE_PROPAGATION_STYLE`. See [Distributed Tracing](#distributed-tracing) for more details.                                                                              |
| `tracing.distributed_tracing.propagation_style`         | `DD_TRACE_PROPAGATION_STYLE` | `nil` | Distributed tracing propagation formats to extract and inject. See [Distributed Tracing](#distributed-tracing) for more details. |
| `tracing.enabled`                                       | `DD_TRACE_ENABLED`             | `true`                                                            | Enables or disables tracing. If set to `false` instrumentation will still run, but no traces are sent to the trace agent.                                                                                                                 |
| `tracing.instrument(<integration-name>, <options...>)`  |                                |                                                                   | Activates instrumentation for a specific library. See [Integration instrumentation](#integration-instrumentation) for more details.                                                                                                       |
| `tracing.log_injection`                                 | `DD_LOGS_INJECTION`            | `true`                                                            | Injects [Trace Correlation](#trace-correlation) information into Rails logs if present. Supports the default logger (`ActiveSupport::TaggedLogging`), `lograge`, and `semantic_logger`.                                                   |
| `tracing.partial_flush.enabled`                         |                                | `false`                                                           | Enables or disables partial flushing. Partial flushing submits completed portions of a trace to the agent. Used when tracing instruments long running tasks (e.g. jobs) with many spans.                                                  |
| `tracing.partial_flush.min_spans_threshold`             |                                | `500`                                                             | The number of spans that must be completed in a trace before partial flushing submits those completed spans.                                                                                                                              |
| `tracing.sampler`                                       |                                | `nil`                                                             | Advanced usage only. Sets a custom `Datadog::Tracing::Sampling::Sampler` instance. If provided, the tracer will use this sampler to determine sampling behavior. See [Application-side sampling](#application-side-sampling) for details. |
| `tracing.sampling.default_rate`                         | `DD_TRACE_SAMPLE_RATE`         | `nil`                                                             | Sets the trace sampling rate between `0.0` (0%) and `1.0` (100%). See [Application-side sampling](#application-side-sampling) for details.                                                                                                  |
| `tracing.sampling.rate_limit`                           | `DD_TRACE_RATE_LIMIT`          | `100` (per second)                                                | Sets a maximum number of traces per second to sample. Set a rate limit to avoid the ingestion volume overages in the case of traffic spikes.                                                                    |
| `tracing.sampling.span_rules`                           | `DD_SPAN_SAMPLING_RULES`,`ENV_SPAN_SAMPLING_RULES_FILE` | `nil`                                    | Sets [Single Span Sampling](#single-span-sampling) rules. These rules allow you to keep spans even when their respective traces are dropped.                                                                                              |
| `tracing.report_hostname`                               | `DD_TRACE_REPORT_HOSTNAME`     | `false`                                                           | Adds hostname tag to traces.                                                                                                                                                                                                              |
| `tracing.test_mode.enabled`                             | `DD_TRACE_TEST_MODE_ENABLED`   | `false`                                                           | Enables or disables test mode, for use of tracing in test suites.                                                                                                                                                                         |
| `tracing.test_mode.trace_flush`                         |                                | `nil`                                                             | Object that determines trace flushing behavior.                                                                                                                                                                                           |

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

By default, the trace agent (not this library, but the program running in the background collecting data from various clients) uses the tags set in the agent config file. You can configure the application to automatically tag your traces and metrics, using the following environment variables:

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

There are two different suggested means of producing diagnostics for tracing:

##### Enabling debug mode

Switching the library into debug mode will produce verbose, detailed logs about tracing activity, including any suppressed errors. This output can be helpful in identifying errors, or confirming trace output to the agent.

You can enable this via `diagnostics.debug = true` or `DD_TRACE_DEBUG`.

```ruby
Datadog.configure { |c| c.diagnostics.debug = true }
```

**We do NOT recommend use of this feature in production or other sensitive environments**, as it can be very verbose under load. It's best to use this in a controlled environment where you can control application load.

##### Enabling startup logs

Startup logs produce a report of tracing state when the application is initially configured. This can be helpful for confirming that configuration and instrumentation is activated correctly.

You can enable this via `diagnostics.startup_logs.enabled = true` or `DD_TRACE_STARTUP_LOGS`.

```ruby
Datadog.configure { |c| c.diagnostics.startup_logs.enabled = true }
```

By default, this will be activated whenever `ddtrace` detects the application is running in a non-development environment.

### Sampling

See [Ingestion Mechanisms](https://docs.datadoghq.com/tracing/trace_pipeline/ingestion_mechanisms/?tab=ruby) for a list of
all the sampling options available.

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

#### Single Span Sampling

You can configure sampling rule that allow you keep spans despite their respective traces being dropped by a trace-level sampling rule.

This allows you to keep important spans when trace-level sampling is applied. Is is not possible to drop spans using Single Span Sampling.

To configure it, see the [Ingestion Mechanisms documentation](https://docs.datadoghq.com/tracing/trace_pipeline/ingestion_mechanisms/?tab=ruby#single-spans).

#### Application-side sampling

While the Datadog agent can sample traces to reduce bandwidth usage, application-side sampling reduces the performance overhead in the host application.

**Application-side sampling drops traces as early as possible. This causes the [Ingestion Controls](https://docs.datadoghq.com/tracing/trace_pipeline/ingestion_controls/) page to not receive enough information to report accurate sampling rates. Use only when reducing the tracing overhead is paramount.**

If you are use this feature, please let us know by [opening an issue on GitHub](https://github.com/DataDog/dd-trace-rb/issues/new), so we can better understand and support your use case.

You can configure *Application-side sampling* with the following settings:

```ruby
# Application-side sampling enabled: Ingestion Controls page will be inaccurate.
sampler = Datadog::Tracing::Sampling::RateSampler.new(0.5) # sample 50% of the traces

Datadog.configure do |c|
  c.tracing.sampler = sampler
end
```

See [Additional Configuration](#additional-configuration) for more details about these settings.

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

#### Distributed header formats

Tracing supports the following distributed trace formats:

 - `Datadog`: **Default**
 - `b3multi`: [B3 multiple-headers](https://github.com/openzipkin/b3-propagation#multiple-headers)
 - `b3`: [B3 single-header](https://github.com/openzipkin/b3-propagation#single-header)
 - `tracecontext`: [W3C Trace Context](https://www.w3.org/TR/trace-context/)
 - `none`: No-op.

You can enable/disable the use of these formats via `Datadog.configure`:

```ruby
Datadog.configure do |c|
  # List of header formats that should be extracted
  c.tracing.distributed_tracing.propagation_extract_style = [ 'tracecontext', 'Datadog', 'b3' ]

  # List of header formats that should be injected
  c.tracing.distributed_tracing.propagation_inject_style = [ 'tracecontext', 'Datadog' ]
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

Then you must enable the request queuing feature. The following options are available for the `:request_queuing` configuration:

| Option             | Description |
| ------------------ | ----------- |
| `:include_request` | A `http_server.queue` span will be the root span of a trace, including the total time spent processing the request *in addition* to the time spent waiting for the request to begin being processed. This is the behavior when the configuration is set to `true`. This is the selected configuration when set to `true`. |
| `:exclude_request` | A `http.proxy.request` span will be the root span of a trace, with the `http.proxy.queue` child span duration representing only the time spent waiting for the request to begin being processed. *This is an experimental feature!* |

For Rack-based applications, see the [documentation](#rack) for details.

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

By default, `ddtrace` will connect to the agent using the first available settings in the listed priority:

1. Via any explicitly provided configuration settings (hostname/port/transport)
2. Via Unix Domain Socket (UDS) located at `/var/run/datadog/apm.socket`
3. Via HTTP over TCP to `127.0.0.1:8126`

However, the tracer can be configured to send its trace data to alternative destinations, or by alternative protocols.

#### Changing default agent hostname and port

To change the agent host or port, provide `DD_AGENT_HOST` and `DD_TRACE_AGENT_PORT`.

OR within a `Datadog.configure` block, provide the following settings:

```ruby
Datadog.configure do |c|
  c.agent.host = '127.0.0.1'
  c.agent.port = 8126
end
```

See [Additional Configuration](#additional-configuration) for more details.

#### Using the Net::HTTP adapter

The `Net` adapter submits traces using `Net::HTTP` over TCP. It is the default transport adapter.

```ruby
Datadog.configure do |c|
  c.tracing.transport_options = proc { |t|
    # Hostname, port, and additional options. :timeout is in seconds.
    t.adapter :net_http, '127.0.0.1', 8126, timeout: 30
  }
end
```

#### Using the Unix Domain Socket (UDS) adapter

The `UnixSocket` adapter submits traces using `Net::HTTP` over Unix socket.

To use, first configure your trace agent to listen by Unix socket, then configure the tracer with:

```ruby
Datadog.configure do |c|
  c.tracing.transport_options = proc { |t|
    # Provide local path to trace agent Unix socket
    t.adapter :unix, '/tmp/ddagent/trace.sock'
  }
end
```

#### Using the transport test adapter

The `Test` adapter is a no-op transport that can optionally buffer requests. For use in test suites or other non-production environments.

```ruby
Datadog.configure do |c|
  c.tracing.transport_options = proc { |t|
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
Datadog.configure do |c|
  c.tracing.transport_options = proc { |t|
    # Initialize and pass an instance of the adapter
    custom_adapter = CustomAdapter.new
    t.adapter custom_adapter
  }
end
```

### Setting the time provider

By default, tracing uses a monotonic clock to measure the duration of spans, and timestamps (`->{ Time.now }`) for the start and end time.

When testing, it might be helpful to use a different time provider.

To change the function that provides timestamps, configure the following:

```ruby
Datadog.configure do |c|
  # For Timecop, for example, `->{ Time.now_without_mock_time }` allows the tracer to use the real wall time.
  c.time_now_provider = -> { Time.now_without_mock_time }
end
```

Span duration calculation will still use the system monotonic clock when available, thus not being affected by this setting.

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
| `runtime.ruby.global_constant_state`        | `gauge` | Global constant cache generation.                                                                     | CRuby ≤ 3.1                                                                                     |
| `runtime.ruby.global_method_state`          | `gauge` | [Global method cache generation.](https://tenderlovemaking.com/2015/12/23/inline-caching-in-mri.html) | [CRuby 2.x](https://docs.ruby-lang.org/en/3.0.0/NEWS_md.html#label-Implementation+improvements) |
| `runtime.ruby.constant_cache_invalidations` | `gauge` | Constant cache invalidations.                                                                         | CRuby ≥ 3.2                                                                                     |
| `runtime.ruby.constant_cache_misses`        | `gauge` | Constant cache misses.                                                                                | CRuby ≥ 3.2                                                                                     |

In addition, all metrics include the following tags:

| Name         | Description                                             |
| ------------ | ------------------------------------------------------- |
| `language`   | Programming language traced. (e.g. `ruby`)              |
| `service`    | List of services this associated with this metric.      |

### OpenTracing

For setting up Datadog with OpenTracing, see our [Configuring OpenTracing](#configuring-opentracing) section for details.

**Configuring Datadog tracer settings**

The underlying Datadog tracer can be configured by passing options (which match `Datadog::Tracer`) when configuring the global tracer:

```ruby
# Where `options` is a Hash of options provided to Datadog::Tracer
OpenTracing.global_tracer = Datadog::OpenTracer::Tracer.new(**options)
```

It can also be configured by using `Datadog.configure` described in the [Additional Configuration](#additional-configuration) section.

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

If traces are missing, enable [debug mode](#debugging-and-diagnostics) to check if messages containing `"Dropping trace. Payload too large"` are logged.

Since debug mode is verbose, **Datadog does not recommend leaving this enabled or enabling this in production.** Disable it after confirming. You can inspect the [Datadog Agent logs](https://docs.datadoghq.com/agent/guide/agent-log-files/) for similar messages.

If you have confirmed that traces are dropped due to large payloads, then enable the [partial_flush](#additional-configuration) setting to break down large traces into smaller chunks.

### Stack level too deep

Datadog tracing collects trace data by adding instrumentation into other common libraries (e.g. Rails, Rack, etc.) Some libraries provide APIs to add this instrumentation, but some do not. In order to add instrumentation into libraries lacking an instrumentation API, Datadog uses a technique called "monkey-patching" to modify the code of that library.

In Ruby version 1.9.3 and earlier, "monkey-patching" often involved the use of [`alias_method`](https://ruby-doc.org/core-3.0.0/Module.html#method-i-alias_method), also known as *method rewriting*, to destructively replace existing Ruby methods. However, this practice would often create conflicts & errors if two libraries attempted to "rewrite" the same method. (e.g. two different APM packages trying to instrument the same method.)

In Ruby 2.0, the [`Module#prepend`](https://ruby-doc.org/core-3.0.0/Module.html#method-i-prepend) feature was introduced. This feature avoids destructive method rewriting and allows multiple "monkey patches" on the same method. Consequently, it has become the safest, preferred means to "monkey patch" code.

Datadog instrumentation almost exclusively uses the `Module#prepend` feature to add instrumentation non-destructively. However, some other libraries (typically those supporting Ruby < 2.0) still use `alias_method` which can create conflicts with Datadog instrumentation, often resulting in `SystemStackError` or `stack level too deep` errors.

As the implementation of `alias_method` exists within those libraries, Datadog generally cannot fix them. However, some libraries have known workarounds:

* `rack-mini-profiler`: [Net::HTTP stack level too deep errors](https://github.com/MiniProfiler/rack-mini-profiler#nethttp-stack-level-too-deep-errors).

For libraries without a known workaround, consider removing the library using `alias` or `Module#alias_method` or separating libraries into different environments for testing.

For any further questions or to report an occurence of this issue, please [reach out to Datadog support](https://docs.datadoghq.com/help)
