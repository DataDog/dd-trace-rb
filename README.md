# Datadog Trace Client

[![CircleCI](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master.svg?style=svg&circle-token=b0bd5ef866ec7f7b018f48731bb495f2d1372cc1)](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master)

`ddtrace` is Datadog’s APM tracing client for Ruby. It is used to trace requests as they flow across web servers, databases and microservices so that developers have great visiblity into bottlenecks and troublesome requests.

## How it works

For a basic overview of what Datadog APM is and how it works, check out our [APM documentation][apm docs].

`ddtrace` wraps Ruby code to take measurements of individual operations within your Ruby application. These measurements, called *spans*, are joined together to form a *trace*, which is sent to the Datadog agent.

Here's an example of a manually traced web request:

```ruby
require 'ddtrace'

get '/posts' do
  Datadog.tracer.trace('web.request', service: 'my-blog', resource: 'GET /posts') do |span|
    # Trace the query to the database
    Datadog.tracer.trace('sql.query', service: 'blog-db') do
      @posts = Posts.order(created_at: :desc).limit(10)
    end

    # Trace the template rendering
    Datadog.tracer.trace('template.render') do
      erb :index
    end
  end
end
```

Which is then presented within Datadog as:

**TODO: Add screenshot of flamegraph here.**

Out of the box, `ddtrace` includes integrations for many popular Ruby gems and frameworks, to make it quick & easy to add instrumentation to your Ruby application.

## Getting started

Setting up tracing for your Ruby application takes only two steps:

1. Setup the Datadog agent
2. Configure your Ruby application

### Setup the Datadog Agent

Before adding the tracing library to your application, you will need to install the Datadog Agent, which receives trace data and forwards it to Datadog.

Check out our instructions for how to [install and configure the Datadog Agent](https://docs.datadoghq.com/tracing/setup). You can also see additional documentation for [tracing Docker applications](https://docs.datadoghq.com/tracing/setup/docker).

### Quickstart for Rails applications

1. Add the `ddtrace` gem to your Gemfile:

    ```ruby
    source 'https://rubygems.org'
    gem 'ddtrace'
    ```

2. Install the gem with `bundle install`
3. Create a `config/initializers/datadog.rb` file containing:

    ```ruby
    Datadog.configure do |c|
      # This will activate auto-instrumentation for Rails
      c.use :rails
    end
    ```

    Within this configuration block, you can also activate additional integrations here; (see [Integration instrumentation](#integration-instrumentation) for more information.)

### Quickstart for Ruby applications

1. Install the gem with `gem install ddtrace`
2. Add a configuration block to your Ruby application:

    ```ruby
    require 'ddtrace'
    Datadog.configure do |c|
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
    require 'ddtrace'
    require 'ddtrace/opentracer'

    # Activate the Datadog tracer for OpenTracing
    OpenTracing.global_tracer = Datadog::OpenTracer::Tracer.new
    ```

3. (Optional) Add a configuration block to your Ruby application to configure Datadog with:

    ```ruby
    Datadog.configure do |c|
      # Configure the Datadog tracer here.
      # Activate integrations, change tracer settings, etc...
      # By default without additional configuration,
      # no additional integrations will be traced, only
      # what you have instrumented with OpenTracing.
    end
    ```

    *NOTE*: Ensure `Datadog.configure` runs only after `OpenTracing.global_tracer` has been configured, to preserve any configuration settings you may set.

4. (Optional) Add or activate additional instrumentation by doing either of the following:
    - Activate Datadog integration instrumentation (see [Integration instrumentation](#integration-instrumentation))
    - Add Datadog manual instrumentation around your code (see [Manual instrumentation](#manual-instrumentation))

### Final steps for installation

After setting up, your services will appear on the [APM services page](https://app.datadoghq.com/apm/services) within a few minutes. Learn more about [using the APM UI][visualization docs].

## Manual Instrumentation

If you aren't using a supported framework instrumentation, you may want to manually instrument your code.

To trace any Ruby code, you can use the `Datadog.tracer.trace` method:

```ruby
Datadog.tracer.trace(name, options) do |span|
  # Wrap this block around the code you want to instrument
  # Additionally, you can modify the span here.
  # e.g. Change the resource name, set tags, etc...
end
```

Where `name` should be a `String` that describes the generic kind of operation being done (e.g. `'web.request'`, or `'request.parse'`)

And `options` is an optional `Hash` that accepts the following parameters:

| Key | Type | Description | Default |
| --- | --- | --- | --- |
| `service`     | `String` | The service name which this span belongs (e.g. `'my-web-service'`) | Tracer `default-service`, `$PROGRAM_NAME` or `'ruby'` |
| `resource`    | `String` | Name of the resource or action being operated on. Traces with the same resource value will be grouped together for the purpose of metrics (but still independently viewable.) Usually domain specific, such as a URL, query, request, etc. (e.g. `'Article#submit'`, `http://example.com/articles/list`.) | `name` of Span. |
| `span_type`   | `String` | The type of the span (such as `'http'`, `'db'`, etc.) | `nil` |
| `child_of`    | `Datadog::Span` / `Datadog::Context` | Parent for this span. If not provided, will automatically become current active span. | `nil` |
| `start_time`  | `Integer` | When the span actually starts. Useful when tracing events that have already happened. | `Time.now.utc` |
| `tags`        | `Hash` | Extra tags which should be added to the span. | `{}` |
| `on_error`    | `Proc` | Handler invoked when a block is provided to trace, and it raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. | `Proc` |

It's highly recommended you set both `service` and `resource` at a minimum. Spans without a `service` or `resource` as `nil` will be discarded by the Datadog agent.

For more explanation of the terminology, and how these options affect how your traces are visualized, check out our [glossary & visualization documentation][visualization docs].

Example of manual instrumentation in action:

```ruby
get '/posts' do
  Datadog.tracer.trace('web.request', service: 'my-blog', resource: 'GET /posts') do |span|
    # Trace the query to the database
    Datadog.tracer.trace('sql.query', service: 'blog-db') do
      @posts = Posts.order(created_at: :desc).limit(10)
    end

    # Add some APM tags
    span.set_tag('http.method', request.request_method)
    span.set_tag('posts.count', @posts.length)

    # Trace the template rendering
    Datadog.tracer.trace('template.render') do
      erb :index
    end
  end
end
```

### Asynchronous tracing

It might not always be possible to wrap `Datadog.tracer.trace` around a block of code. Some event or notification based instrumentation might only notify you when an event begins or ends.

To trace these operations, you can trace code asynchronously by calling `Datadog.tracer.trace` without a block:

```ruby
# Some instrumentation framework calls this after an event finishes...
def db_query(start, finish, query)
  span = Datadog.tracer.trace('database.query')
  span.resource = query
  span.start_time = start
  span.finish(finish)
end
```

Calling `Datadog.tracer.trace` without a block will cause the function to return a `Datadog::Span` that is started, but not finished. You can then modify this span however you wish, then close it `finish`.

*You must not leave any unfinished spans.* If any spans are left open when the trace completes, the trace will be discarded. You can [activate debug mode](#tracer-settings) to check for warnings if you suspect this might be happening.

To avoid this scenario when handling start/finish events, you can use `Datadog.tracer.active_span` to get the current active span.

```ruby
# e.g. ActiveSupport::Notifications calls this when an event starts
def start(name, id, payload)
  # Start a span
  Datadog.tracer.trace(name)
end

# e.g. ActiveSupport::Notifications calls this when an event finishes
def finish(name, id, payload)
  # Retrieve current active span (thread-safe)
  current_span = Datadog.tracer.active_span
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

current_span = Datadog.tracer.active_span
current_span.set_tag('my_tag', 'my_value') unless current_span.nil?
```

You can also get the root span of the current active trace using the `active_root_span` method. This method will return `nil` if there is no active trace.

```ruby
# e.g. adding tag to active root span

current_root_span = Datadog.tracer.active_root_span
current_root_span.set_tag('my_tag', 'my_value') unless current_root_span.nil?
```

## Integration instrumentation

Many popular libraries and frameworks are supported out-of-the-box, which can be auto-instrumented. Although they are not activated automatically, they can be easily activated and configured by using `Datadog.configure`:

```ruby
Datadog.configure do |c|
  # Activates and configures an integration
  c.use :integration_key, options
end
```

`options` is a `Hash` of integration-specific configuration settings (optional.)

For a list of available integrations, and their configuration options, please refer to the following:

| Name                     | Key                        | Versions Supported       | How to configure                                                                                           | Gem source                                                                     |
| ------------------------ | -------------------------- | ------------------------ | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Action View              | `action_view`              | `>= 3.2`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#action-view)*              | *[Link](https://github.com/rails/rails/tree/master/actionview)*                |
| Active Model Serializers | `active_model_serializers` | `>= 0.9`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#active-model-serializers)* | *[Link](https://github.com/rails-api/active_model_serializers)*                |
| Action Pack              | `action_pack`              | `>= 3.2`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#action-pack)*              | *[Link](https://github.com/rails/rails/tree/master/actionpack)*                |
| Active Record            | `active_record`            | `>= 3.2`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#active-record)*            | *[Link](https://github.com/rails/rails/tree/master/activerecord)*              |
| Active Support           | `active_support`           | `>= 3.2`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#active-support)*           | *[Link](https://github.com/rails/rails/tree/master/activesupport)*             |
| AWS                      | `aws`                      | `>= 2.0`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#aws)*                      | *[Link](https://github.com/aws/aws-sdk-ruby)*                                  |
| Concurrent Ruby          | `concurrent_ruby`          | `>= 0.9`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#concurrent-ruby)*          | *[Link](https://github.com/ruby-concurrency/concurrent-ruby)*                  |
| Dalli                    | `dalli`                    | `>= 2.7`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#dalli)*                    | *[Link](https://github.com/petergoldstein/dalli)*                              |
| DelayedJob               | `delayed_job`              | `>= 4.1`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#delayedjob)*               | *[Link](https://github.com/collectiveidea/delayed_job)*                        |
| Elastic Search           | `elasticsearch`            | `>= 6.0`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#elastic-search)*           | *[Link](https://github.com/elastic/elasticsearch-ruby)*                        |
| Ethon                    | `ethon`                    | `>= 0.11.0`              | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#ethon)*                    | *[Link](https://github.com/typhoeus/ethon)*                                    |
| Excon                    | `excon`                    | `>= 0.62`                | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#excon)*                    | *[Link](https://github.com/excon/excon)*                                       |
| Faraday                  | `faraday`                  | `>= 0.14`                | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#faraday)*                  | *[Link](https://github.com/lostisland/faraday)*                                |
| Grape                    | `grape`                    | `>= 1.0`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#grape)*                    | *[Link](https://github.com/ruby-grape/grape)*                                  |
| GraphQL                  | `graphql`                  | `>= 1.7.9`               | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#graphql)*                  | *[Link](https://github.com/rmosolgo/graphql-ruby)*                             |
| gRPC                     | `grpc`                     | `>= 1.10`                | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#grpc)*                     | *[Link](https://github.com/grpc/grpc/tree/master/src/rubyc)*                   |
| MongoDB                  | `mongo`                    | `>= 2.0`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#mongodb)*                  | *[Link](https://github.com/mongodb/mongo-ruby-driver)*                         |
| MySQL2                   | `mysql2`                   | `>= 0.3.21`              | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#mysql2)*                   | *[Link](https://github.com/brianmario/mysql2)*                                 |
| Net/HTTP                 | `http`                     | *(Any supported Ruby)*   | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#nethttp)*                  | *[Link](https://ruby-doc.org/stdlib-2.4.0/libdoc/net/http/rdoc/Net/HTTP.html)* |
| Racecar                  | `racecar`                  | `>= 0.3.5`               | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#racecar)*                  | *[Link](https://github.com/zendesk/racecar)*                                   |
| Rack                     | `rack`                     | `>= 1.4.7`               | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#rack)*                     | *[Link](https://github.com/rack/rack)*                                         |
| Rails                    | `rails`                    | `>= 3.2`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#rails)*                    | *[Link](https://github.com/rails/rails)*                                       |
| Rake                     | `rake`                     | `>= 12.0`                | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#rake)*                     | *[Link](https://github.com/ruby/rake)*                                         |
| Redis                    | `redis`                    | `>= 3.2, < 4.0`          | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#redis)*                    | *[Link](https://github.com/redis/redis-rb)*                                    |
| Resque                   | `resque`                   | `>= 1.0, < 2.0`          | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#resque)*                   | *[Link](https://github.com/resque/resque)*                                     |
| Rest Client              | `rest-client`              | `>= 1.8`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#rest-client)*              | *[Link](https://github.com/rest-client/rest-client)*                           |
| Sequel                   | `sequel`                   | `>= 3.41`                | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#sequel)*                   | *[Link](https://github.com/jeremyevans/sequel)*                                |
| Shoryuken                | `shoryuken`                | `>= 4.0.2`               | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#shoryuken)*                | *[Link](https://github.com/phstc/shoryuken)*                                   |
| Sidekiq                  | `sidekiq`                  | `>= 3.5.4`               | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#sidekiq)*                  | *[Link](https://github.com/mperham/sidekiq)*                                   |
| Sinatra                  | `sinatra`                  | `>= 1.4.5`               | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#sinatra)*                  | *[Link](https://github.com/sinatra/sinatra)*                                   |
| Sucker Punch             | `sucker_punch`             | `>= 2.0`                 | *[Link](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#sucker-punch)*             | *[Link](https://github.com/brandonhilkert/sucker_punch)*                       |

## Other features

### Distributed tracing

Distributed tracing allows you to see how traces for web requests (and other cross-process communication) traverse other applications within your infrastructure, giving you greater visibility, particularly with microservices.

**TODO: Add flamegraph here**

Distributed tracing is active by default in `ddtrace` for all integrations that are capable of distributed tracing.

Read more about how distributed tracing works, and how to use it in `ddtrace` in our [documentation](https://github.com/DataDog/dd-trace-rb/blob/master/docs/DistributedTracing.md).

### Correlating traces with logs

Traces produced by `ddtrace` can be correlated with your log entries for easy discovery.

**TODO: Add screenshot showing correlated log message here**

It can be quickly activated with Lograge, Rails or other Ruby applications; read more about how to configure and activate this in our [documentation](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Correlation.md#with-logs).

### Runtime metrics

`ddtrace` can provide insight into your runtime environment by collecting metrics about garbage collection within the Ruby process.

**TODO: Add screenshot showing runtime metric graphs here**

The collection of these metrics is disabled by default, but can be enabled with the use of `dogstatsd-ruby` and minimal configuration. See our [documentation](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Metrics.md#for-application-runtime) for more details.

### HTTP request queuing

`ddtrace` can add also instrumentation for web server queue times, via the use of HTTP headers.

**TODO: Add screenshot showing flamegraph with HTTP server span here**

Read more about how to enable this feature in our [documentation](https://github.com/DataDog/dd-trace-rb/blob/master/docs/WebServers.md#http-request-queuing).

### Using Datadog with OpenTracing

Datadog supports interoperatibility with OpenTracing instrumentation out-of-the box.

**TODO: Add screenshot showing flamegraph with OpenTracing instrumentation here**

See the [Quickstart for OpenTracing](#quickstart-for-opentracing) section for setup instructions, or the [documentation](https://github.com/DataDog/dd-trace-rb/blob/master/docs/OpenTracing.md) for more details about how `ddtrace` works with OpenTracing.

## Compatibility

**Supported Ruby interpreters**:

| Type  | Documentation              | Version | Support type                         | Gem version support |
| ----- | -------------------------- | -----   | ------------------------------------ | ------------------- |
| MRI   | https://www.ruby-lang.org/ | 2.6     | Full                                 | Latest              |
|       |                            | 2.5     | Full                                 | Latest              |
|       |                            | 2.4     | Full                                 | Latest              |
|       |                            | 2.3     | Full                                 | Latest              |
|       |                            | 2.2     | Full                                 | Latest              |
|       |                            | 2.1     | Full                                 | Latest              |
|       |                            | 2.0     | Full                                 | Latest              |
|       |                            | 1.9.3   | Maintenance (until August 6th, 2020) | < 0.27.0            |
|       |                            | 1.9.1   | Maintenance (until August 6th, 2020) | < 0.27.0            |
| JRuby | http://jruby.org/          | 9.1.5   | Alpha                                | Latest              |

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

## Contributing

Contributions to `ddtrace` are welcome and encouraged! Please read through our [guidelines][contribution docs] for more details on how the contribution process works, and our [development guide][development docs] for technical reference.

## Further Reading

For descriptions of terminology used in APM, take a look at the [official documentation][visualization docs].

The API documentation for our latest release can be found in our [gem documentation][gem docs].

For more details about other facets of `ddtrace`:

 - [Supported integrations](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md)
 - [Advanced usage](https://github.com/DataDog/dd-trace-rb/blob/master/docs/AdvancedUsage.md)
    - [Tracer settings](https://github.com/DataDog/dd-trace-rb/blob/master/docs/AdvancedUsage.md#adjusting-tracer-settings)
    - [Customizing trace logs](https://github.com/DataDog/dd-trace-rb/blob/master/docs/AdvancedUsage.md#custom-logging)
    - [Setting the environment and other default tags](https://github.com/DataDog/dd-trace-rb/blob/master/docs/AdvancedUsage.md#environment-and-tags)
    - [Configuring how trace data is sent](https://github.com/DataDog/dd-trace-rb/blob/master/docs/AdvancedUsage.md#configuring-the-transport-layer)
    - [Sampling](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Sampling.md)
        - [Priority sampling](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Sampling.md#priority-sampling)
 - [Distributed tracing](https://github.com/DataDog/dd-trace-rb/blob/master/docs/DistributedTracing.md)
 - [Web servers](https://github.com/DataDog/dd-trace-rb/blob/master/docs/WebServers.md)
    - [Measuring HTTP request queue times](https://github.com/DataDog/dd-trace-rb/blob/master/docs/WebServers.md#http-request-queuing)
 - [Using the processing pipeline](https://github.com/DataDog/dd-trace-rb/blob/master/docs/ProcessingPipeline.md)
    - [To filter spans](https://github.com/DataDog/dd-trace-rb/blob/master/docs/ProcessingPipeline.md#filtering)
    - [To modify spans](https://github.com/DataDog/dd-trace-rb/blob/master/docs/ProcessingPipeline.md#processing)
 - [Correlating traces with logs](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Correlation.md#with-logs)
 - [Metrics](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Metrics.md)
    - [For the application runtime](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Metrics.md#for-application-runtime)
 - [Using Datadog with OpenTracing](https://github.com/DataDog/dd-trace-rb/blob/master/docs/OpenTracing.md)

[apm docs]: https://docs.datadoghq.com/tracing/
[visualization docs]: https://docs.datadoghq.com/tracing/visualization/
[gem docs]: http://gems.datadoghq.com/trace/docs/
[contribution docs]: https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md
[development docs]: https://github.com/DataDog/dd-trace-rb/blob/master/docs/DevelopmentGuide.md