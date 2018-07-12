# Datadog Trace Client

``ddtrace`` is Datadog’s tracing client for Ruby. It is used to trace requests as they flow across web servers,
databases and microservices so that developers have great visiblity into bottlenecks and troublesome requests.

## Getting started

For a basic product overview, check out our [setup documentation][setup docs].

For details about contributing, check out the [development guide][development docs].

For descriptions of terminology used in APM, take a look at the [official documentation][visualization docs].

[setup docs]: https://docs.datadoghq.com/tracing/setup/ruby/
[development docs]: https://github.com/DataDog/dd-trace-rb/blob/master/README.md#development
[visualization docs]: https://docs.datadoghq.com/tracing/visualization/

## Table of Contents

 - [Compatibility](#compatibility)
 - [Installation](#installation)
     - [Quickstart for Rails applications](#quickstart-for-rails-applications)
     - [Quickstart for Ruby applications](#quickstart-for-ruby-applications)
 - [Manual instrumentation](#manual-instrumentation)
 - [Integration instrumentation](#integration-instrumentation)
     - [Active Record](#active-record)
     - [AWS](#aws)
     - [Dalli](#dalli)
     - [Elastic Search](#elastic-search)
     - [Excon](#excon)
     - [Faraday](#faraday)
     - [gRPC](#grpc)
     - [Grape](#grape)
     - [GraphQL](#graphql)
     - [MongoDB](#mongodb)
     - [Net/HTTP](#nethttp)
     - [Racecar](#racecar)
     - [Rack](#rack)
     - [Rails](#rails)
     - [Rake](#rake)
     - [Redis](#redis)
     - [Resque](#resque)
     - [Sequel](#sequel)
     - [Sidekiq](#sidekiq)
     - [Sinatra](#sinatra)
     - [Sucker Punch](#sucker-punch)
 - [Advanced configuration](#advanced-configuration)
     - [Tracer settings](#tracer-settings)
     - [Custom logging](#custom-logging)
     - [Environment and tags](#environment-and-tags)
     - [Sampling](#sampling)
         - [Priority sampling](#priority-sampling)
     - [Distributed tracing](#distributed-tracing)
     - [HTTP request queuing](#http-request-queuing)
     - [Processing pipeline](#processing-pipeline)
         - [Filtering](#filtering)
         - [Processing](#processing)

## Compatibility

**Supported Ruby interpreters**:

| Type  | Documentation              | Version | Support type |
| ----- | -------------------------- | -----   | ------------ |
| MRI   | https://www.ruby-lang.org/ | 1.9.1   | Experimental |
|       |                            | 1.9.3   | Full         |
|       |                            | 2.0     | Full         |
|       |                            | 2.1     | Full         |
|       |                            | 2.2     | Full         |
|       |                            | 2.3     | Full         |
|       |                            | 2.4     | Full         |
| JRuby | http://jruby.org/          | 9.1.5   | Experimental |

*Full* support indicates all tracer features are available.

*Experimental* indicates most features should be available, but unverified.

**Supported web servers**:

| Type      | Documentation                     | Version      | Support type |
| --------- | --------------------------------- | ------------ | ------------ |
| Puma      | http://puma.io/                   | 2.16+ / 3.6+ | Full         |
| Unicorn   | https://bogomips.org/unicorn/     | 4.8+ / 5.1+  | Full         |
| Passenger | https://www.phusionpassenger.com/ | 5.0+         | Full         |

## Installation

The following steps will help you quickly start tracing your Ruby application.

### Setup the Datadog Agent

The Ruby APM tracer sends trace data through the Datadog Agent.

[Install and configure the Datadog Agent](https://docs.datadoghq.com/tracing/setup), see additional documentation for [tracing Docker applications](https://docs.datadoghq.com/tracing/setup/docker/).

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

    You can also activate additional integrations here (see [Integration instrumentation](#integration-instrumentation))

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
    1. Activate integration instrumentation (see [Integration instrumentation](#integration-instrumentation))
    2. Add manual instrumentation around your code (see [Manual instrumentation](#manual-instrumentation))

### Final steps for installation

After setting up, your services will appear on the [APM services page](https://app.datadoghq.com/apm/services) within a few minutes. Learn more about [using the APM UI][visualization docs].

## Manual Instrumentation

If you aren't using a supported framework instrumentation, you may want to to manually instrument your code.

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
| ``service``     | `String` | The service name which this span belongs (e.g. `'my-web-service'`) | Tracer `default-service`, `$PROGRAM_NAME` or `'ruby'` |
| ``resource``    | `String` | Name of the resource or action being operated on. Traces with the same resource value will be grouped together for the purpose of metrics (but still independently viewable.) Usually domain specific, such as a URL, query, request, etc. (e.g. `'Article#submit'`, `http://example.com/articles/list`.) | `name` of Span. |
| ``span_type``   | `String` | The type of the span (such as `'http'`, `'db'`, etc.) | `nil` |
| ``child_of``    | `Datadog::Span` / `Datadog::Context` | Parent for this span. If not provided, will automatically become current active span. | `nil` |
| ``start_time``  | `Integer` | When the span actually starts. Useful when tracing events that have already happened. | `Time.now.utc` |
| ``tags``        | `Hash` | Extra tags which should be added to the span. | `{}` |
| ``on_error``    | `Proc` | Handler invoked when a block is provided to trace, and it raises an error. Provided `span` and `error` as arguments. Sets error on the span by default. | `proc { |span, error| span.set_error(error) unless span.nil? }` |

It's highly recommended you set both `service` and `resource` at a minimum. Spans without a `service` or `resource` as `nil` will be discarded by the Datadog agent.

Example of manual instrumentation in action:

```ruby
get '/posts' do
  Datadog.tracer.trace('web.request', service: 'my-blog', resource: 'GET /posts') do |span|
    # Trace the activerecord call
    Datadog.tracer.trace('posts.fetch') do
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

**Asynchronous tracing**

It might not always be possible to wrap `Datadog.tracer.trace` around a block of code. Some event or notification based instrumentation might only notify you when an event begins or ends.

To trace these operations, you can trace code asynchronously by calling `Datadog.tracer.trace` without a block:

```ruby
# Some instrumentation framework calls this after an event began and finished...
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
#####Enriching traces from nested methods

You can tag additional information to current active span from any method. Note however that if the method is called and there is no span currently active `active_span` will be nil.

```ruby
# e.g. adding tag to active span

current_span = Datadog.tracer.active_span
current_span.set_tag('my_tag', 'my_value') unless current_span.nil?
```

## Integration instrumentation

Many popular libraries and frameworks are supported out-of-the-box, which can be auto-instrumented. Although they are not activated automatically, they can be easily activated and configured by using the `Datadog.configure` API:

```ruby
Datadog.configure do |c|
  # Activates and configures an integration
  c.use :integration_name, options
end
```

`options` is a `Hash` of integration-specific configuration settings.

For a list of available integrations, and their configuration options, please refer to the following:

| Name           | Key             | Versions Supported     | How to configure          | Gem source                                                                     |
| -------------- | --------------- | ---------------------- | ------------------------- | ------------------------------------------------------------------------------ |
| Active Record  | `active_record` | `>= 3.2, < 5.2`        | *[Link](#active-record)*  | *[Link](https://github.com/rails/rails/tree/master/activerecord)*              |
| AWS            | `aws`           | `>= 2.0`               | *[Link](#aws)*            | *[Link](https://github.com/aws/aws-sdk-ruby)*                                  |
| Dalli          | `dalli`         | `>= 2.7`               | *[Link](#dalli)*          | *[Link](https://github.com/petergoldstein/dalli)*                              |
| Elastic Search | `elasticsearch` | `>= 6.0`               | *[Link](#elastic-search)* | *[Link](https://github.com/elastic/elasticsearch-ruby)*                        |
| Excon          | `excon`         | `>= 0.62`              | *[Link](#excon)*          | *[Link](https://github.com/excon/excon)*                                       |
| Faraday        | `faraday`       | `>= 0.14`              | *[Link](#faraday)*        | *[Link](https://github.com/lostisland/faraday)*                                |
| gRPC           | `grpc`          | `>= 1.10`              | *[Link](#grpc)*           | *[Link](https://github.com/grpc/grpc/tree/master/src/rubyc)*                   |
| Grape          | `grape`         | `>= 1.0`               | *[Link](#grape)*          | *[Link](https://github.com/ruby-grape/grape)*                                  |
| GraphQL        | `graphql`       | `>= 1.7.9`             | *[Link](#graphql)*        | *[Link](https://github.com/rmosolgo/graphql-ruby)*                             |
| MongoDB        | `mongo`         | `>= 2.0, < 2.5`        | *[Link](#mongodb)*        | *[Link](https://github.com/mongodb/mongo-ruby-driver)*                         |
| Net/HTTP       | `http`          | *(Any supported Ruby)* | *[Link](#nethttp)*        | *[Link](https://ruby-doc.org/stdlib-2.4.0/libdoc/net/http/rdoc/Net/HTTP.html)* |
| Racecar        | `racecar`       | `>= 0.3.5`             | *[Link](#racecar)*        | *[Link](https://github.com/zendesk/racecar)*                                   |
| Rack           | `rack`          | `>= 1.4.7`             | *[Link](#rack)*           | *[Link](https://github.com/rack/rack)*                                         |
| Rails          | `rails`         | `>= 3.2, < 5.2`        | *[Link](#rails)*          | *[Link](https://github.com/rails/rails)*                                       |
| Rake           | `rake`          | `>= 12.0`              | *[Link](#rake)*           | *[Link](https://github.com/ruby/rake)*                                         |
| Redis          | `redis`         | `>= 3.2, < 4.0`        | *[Link](#redis)*          | *[Link](https://github.com/redis/redis-rb)*                                    |
| Resque         | `resque`        | `>= 1.0, < 2.0`        | *[Link](#resque)*         | *[Link](https://github.com/resque/resque)*                                     |
| Sequel         | `sequel`        | `>= 3.41`              | *[Link](#sequel)*         | *[Link](https://github.com/jeremyevans/sequel)*                                |
| Sidekiq        | `sidekiq`       | `>= 4.0`               | *[Link](#sidekiq)*        | *[Link](https://github.com/mperham/sidekiq)*                                   |
| Sinatra        | `sinatra`       | `>= 1.4.5`             | *[Link](#sinatra)*        | *[Link](https://github.com/sinatra/sinatra)*                                   |
| Sucker Punch   | `sucker_punch`  | `>= 2.0`               | *[Link](#sucker-punch)*   | *[Link](https://github.com/brandonhilkert/sucker_punch)*                       |

### Active Record

Most of the time, Active Record is set up as part of a web framework (Rails, Sinatra...) however it can be set up alone:

```ruby
require 'tmpdir'
require 'sqlite3'
require 'active_record'
require 'ddtrace'

Datadog.configure do |c|
  c.use :active_record, options
end

Dir::Tmpname.create(['test', '.sqlite']) do |db|
  conn = ActiveRecord::Base.establish_connection(adapter: 'sqlite3',
                                                 database: db)
  conn.connection.execute('SELECT 42') # traced!
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for database portion of `active_record` instrumentation. | Name of database adapter (e.g. `mysql2`) |
| ``orm_service_name`` | Service name used for the Ruby ORM portion of `active_record` instrumentation. Overrides service name for ORM spans if explicitly set, which otherwise inherit their service from their parent.  | ``active_record`` |

**Configuring trace settings per database**

You can provide the `databases` option to configure trace settings by database connection:

```ruby
# Provide a `:describes` option with a connection key.
# Any of the following keys are acceptable, and equivalent to one another.
# If a block is provided, it yields a Settings object that
# accepts any of the configuration options listed above.

Datadog.configure do |c|
  # Symbol matching your database connection in config/database.yml
  # Only available if you are using Rails with ActiveRecord.
  c.use :active_record, describes: :secondary_database, service_name: 'secondary-db'

  c.use :active_record, describes: :secondary_database do |second_db|
    second_db.service_name = 'secondary-db'
  end

  # Connection string with the following connection settings:
  # Adapter, user, host, port, database
  c.use :active_record, describes: 'mysql2://root@127.0.0.1:3306/mysql', service_name: 'secondary-db'

  # Hash with following connection settings
  # Adapter, user, host, port, database
  c.use :active_record, describes: {
      adapter:  'mysql2',
      host:     '127.0.0.1',
      port:     '3306',
      database: 'mysql',
      username: 'root'
    },
    service_name: 'secondary-db'
end
```

If ActiveRecord traces an event that uses a connection described within `databases`, it will use the trace settings assigned to that connection. If the connection does not match any in the `databases` option, it will use settings defined by `c.use :active_record` instead.

### AWS

The AWS integration will trace every interaction (e.g. API calls) with AWS services (S3, ElastiCache etc.).

```ruby
require 'aws-sdk'
require 'ddtrace'

Datadog.configure do |c|
  c.use :aws, options
end

Aws::S3::Client.new.list_buckets # traced call
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `aws` instrumentation | aws |

### Dalli

Dalli integration will trace all calls to your ``memcached`` server:

```ruby
require 'dalli'
require 'ddtrace'

Datadog.configure do |c|
  c.use :dalli, service_name: 'dalli'
end

client = Dalli::Client.new('localhost:11211', options)
client.set('abc', 123)
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `dalli` instrumentation | memcached |

### Elastic Search

The Elasticsearch integration will trace any call to ``perform_request`` in the ``Client`` object:

```ruby
require 'elasticsearch/transport'
require 'ddtrace'

Datadog.configure do |c|
  c.use :elasticsearch, options
end

# now do your Elastic Search stuff, eg:
client = Elasticsearch::Client.new url: 'http://127.0.0.1:9200'
response = client.perform_request 'GET', '_cluster/health'
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `elasticsearch` instrumentation | elasticsearch |
| ``quantize`` | Hash containing options for quantization. May include `:show` with an Array of keys to not quantize (or `:all` to skip quantization), or `:exclude` with Array of keys to exclude entirely. | {} |

### Excon

The `excon` integration is available through the `ddtrace` middleware:

```ruby
require 'excon'
require 'ddtrace'

# Configure default Excon tracing behavior
Datadog.configure do |c|
  c.use :excon, service_name: 'excon'
end

connection = Excon.new('https://example.com')
connection.get
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| `service_name` | Service name for Excon instrumentation. When provided to middleware for a specific connection, it applies only to that connection object. | `'excon'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `false` |
| `error_handler` | A `Proc` that accepts a `response` parameter. If it evaluates to a *truthy* value, the trace span is marked as an error. By default only sets 5XX responses as errors. | `nil` |
| `tracer` | A `Datadog::Tracer` instance used to instrument the application. Usually you don't need to set that. | `Datadog.tracer` |

**Configuring connections to use different settings**

If you use multiple connections with Excon, you can give each of them different settings by configuring their constructors with middleware:

```ruby
# Wrap the Datadog tracing middleware around the default middleware stack
Excon.new(
  'http://example.com',
  middlewares: Datadog::Contrib::Excon::Middleware.with(options).around_default_stack
)

# Insert the middleware into a custom middleware stack.
# NOTE: Trace middleware must be inserted after ResponseParser!
Excon.new(
  'http://example.com',
  middlewares: [
    Excon::Middleware::ResponseParser,
    Datadog::Contrib::Excon::Middleware.with(options),
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

Datadog.configure do |c|
  c.use :faraday, service_name: 'faraday' # global service name
end

connection = Faraday.new('https://example.com') do |builder|
  builder.use(:ddtrace, options)
  builder.adapter Faraday.default_adapter
end

connection.get('/foo')
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| `service_name` | Service name for Faraday instrumentation. When provided to middleware for a specific connection, it applies only to that connection object. | `'faraday'` |
| `split_by_domain` | Uses the request domain as the service name when set to `true`. | `false` |
| `distributed_tracing` | Enables [distributed tracing](#distributed-tracing) | `false` |
| `error_handler` | A `Proc` that accepts a `response` parameter. If it evaluates to a *truthy* value, the trace span is marked as an error. By default only sets 5XX responses as errors. | ``5xx`` evaluated as errors |
| `tracer` | A `Datadog::Tracer` instance used to instrument the application. Usually you don't need to set that. | `Datadog.tracer` |

### gRPC

The `grpc` integration adds both client and server interceptors, which run as middleware prior to executing the service's remote procedure call. As gRPC applications are often distributed, the integration shares trace information between client and server.

To setup your integration, use the ``Datadog.configure`` method like so:

```ruby
require 'grpc'
require 'ddtrace'

Datadog.configure do |c|
  c.use :grpc, options
end

# run your application normally

# server side
server = GRPC::RpcServer.new
server.add_http2_port('localhost:50051', :this_port_is_insecure)
server.handle(Demo)
server.run_till_terminated

# client side
client = Demo.rpc_stub_class.new('localhost:50051', :this_channel_is_insecure)
client.my_endpoint(DemoMessage.new(contents: 'hello!'))
```

In situations where you have multiple clients calling multiple distinct services, you may pass the Datadog interceptor directly, like so

```ruby
configured_interceptor = Datadog::Contrib::GRPC::DatadogInterceptor::Client.new do |c|
  c.service_name = "Alternate"
end

alternate_client = Demo::Echo::Service.rpc_stub_class.new(
  'localhost:50052',
  :this_channel_is_insecure,
  :interceptors => [configured_interceptor]
)
```

The integration will ensure that the ``configured_interceptor`` establishes a unique tracing setup for that client instance.

The following configuration options are supported:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `grpc` instrumentation | grpc |
| ``tracer`` | Datadog tracer used for `grpc` instrumentation | Datadog.tracer |

### Grape

The Grape integration adds the instrumentation to Grape endpoints and filters. This integration can work side by side with other integrations like Rack and Rails.

To activate your integration, use the ``Datadog.configure`` method before defining your Grape application:

```ruby
# api.rb
require 'grape'
require 'ddtrace'

Datadog.configure do |c|
  c.use :grape, options
end

# then define your application
class RackTestingAPI < Grape::API
  desc 'main endpoint'
  get :success do
    'Hello world!'
  end
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `grape` instrumentation | grape |

### GraphQL

The GraphQL integration activates instrumentation for GraphQL queries.

To activate your integration, use the ``Datadog.configure`` method:

```ruby
# Inside Rails initializer or equivalent
Datadog.configure do |c|
  c.use :graphql,
        service_name: 'graphql',
        schemas: [YourSchema]
end

# Then run a GraphQL query
YourSchema.execute(query, variables: {}, context: {}, operation_name: nil)
```

The `use :graphql` method accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `graphql` instrumentation | ``ruby-graphql`` |
| ``schemas`` | Required. Array of `GraphQL::Schema` objects which to trace. Tracing will be added to all the schemas listed, using the options provided to this configuration. If you do not provide any, then tracing will not be activated. | ``[]`` |
| ``tracer`` | A ``Datadog::Tracer`` instance used to instrument the application. Usually you don't need to set that. | ``Datadog.tracer`` |

**Manually configuring GraphQL schemas**

If you prefer to individually configure the tracer settings for a schema (e.g. you have multiple schemas with different service names), in the schema definition, you can add the following [using the GraphQL API](http://graphql-ruby.org/queries/tracing.html):

```ruby
YourSchema = GraphQL::Schema.define do
  use(
    GraphQL::Tracing::DataDogTracing,
    service: 'graphql'
  )
end
```

Or you can modify an already defined schema:

```ruby
YourSchema.define do
  use(
    GraphQL::Tracing::DataDogTracing,
    service: 'graphql'
  )
end
```

Do *not* `use :graphql` in `Datadog.configure` if you choose to configure manually, as to avoid double tracing. These two means of configuring GraphQL tracing are considered mutually exclusive.

### MongoDB

The integration traces any `Command` that is sent from the [MongoDB Ruby Driver](https://github.com/mongodb/mongo-ruby-driver) to a MongoDB cluster. By extension, Object Document Mappers (ODM) such as Mongoid are automatically instrumented if they use the official Ruby driver. To activate the integration, simply:

```ruby
require 'mongo'
require 'ddtrace'

Datadog.configure do |c|
  c.use :mongo, options
end

# now create a MongoDB client and use it as usual:
client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'artists')
collection = client[:people]
collection.insert_one({ name: 'Steve' })

# In case you want to override the global configuration for a certain client instance
Datadog.configure(client, service_name: 'mongodb-primary')
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `mongo` instrumentation | mongodb |
| ``quantize`` | Hash containing options for quantization. May include `:show` with an Array of keys to not quantize (or `:all` to skip quantization), or `:exclude` with Array of keys to exclude entirely. | ```{ show: [:collection, :database, :operation]  }``` |

### Net/HTTP

The Net/HTTP integration will trace any HTTP call using the standard lib Net::HTTP module.

```ruby
require 'net/http'
require 'ddtrace'

Datadog.configure do |c|
  c.use :http, options
end

Net::HTTP.start('127.0.0.1', 8080) do |http|
  request = Net::HTTP::Get.new '/index'
  response = http.request request
end

content = Net::HTTP.get(URI('http://127.0.0.1/index.html'))
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `http` instrumentation | net/http |
| ``distributed_tracing`` | Enables [distributed tracing](#distributed-tracing) | ``false`` |
| ``tracer`` | A ``Datadog::Tracer`` instance used to instrument the application. Usually you don't need to set that. | ``Datadog.tracer`` |

If you wish to configure each connection object individually, you may use the ``Datadog.configure`` as it follows:

```ruby
client = Net::HTTP.new(host, port)
Datadog.configure(client, options)
```

### Racecar

The Racecar integration provides tracing for Racecar jobs.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.use :racecar, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `racecar` instrumentation | racecar |
| ``tracer`` | A ``Datadog::Tracer`` instance used to instrument the application. Usually you don't need to set that. | ``Datadog.tracer`` |

### Rack

The Rack integration provides a middleware that traces all requests before they reach the underlying framework or application. It responds to the Rack minimal interface, providing reasonable values that can be retrieved at the Rack level.

This integration is automatically activated with web frameworks like Rails. If you're using a plain Rack application, just enable the integration it to your ``config.ru``:

```ruby
# config.ru example
require 'ddtrace'

Datadog.configure do |c|
  c.use :rack, options
end

use Datadog::Contrib::Rack::TraceMiddleware

app = proc do |env|
  [ 200, {'Content-Type' => 'text/plain'}, ['OK'] ]
end

run app
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used when tracing application requests | rack |
| ``distributed_tracing`` | Enables [distributed tracing](#distributed-tracing) so that this service trace is connected with a trace of another service if tracing headers are received | `false` |
| ``middleware_names`` | Enable this if you want to use the middleware classes as the resource names for `rack` spans. Must provide the ``application`` option with it. | ``false`` |
| ``quantize`` | Hash containing options for quantization. May include `:query` or `:fragment`. | {} |
| ``quantize.query`` | Hash containing options for query portion of URL quantization. May include `:show` or `:exclude`. See options below. Option must be nested inside the `quantize` option. | {} |
| ``quantize.query.show`` | Defines which values should always be shown. Shows no values by default. May be an Array of strings, or `:all` to show all values. Option must be nested inside the `query` option. | ``nil`` |
| ``quantize.query.exclude`` | Defines which values should be removed entirely. Excludes nothing by default. May be an Array of strings, or `:all` to remove the query string entirely. Option must be nested inside the `query` option. | ``nil`` |
| ``quantize.fragment`` | Defines behavior for URL fragments. Removes fragments by default. May be `:show` to show URL fragments. Option must be nested inside the `quantize` option. | ``nil`` |
| ``application`` | Your Rack application. Necessary for enabling middleware resource names. | ``nil`` |
| ``tracer`` | A ``Datadog::Tracer`` instance used to instrument the application. Usually you don't need to set that. | ``Datadog.tracer`` |
| ``request_queuing`` | Track HTTP request time spent in the queue of the frontend server. See [HTTP request queuing](#http-request-queuing) for setup details. Set to `true` to enable. | ``false`` |
| ``web_service_name`` | Service name for frontend server request queuing spans. (e.g. `'nginx'`) | ``'web-server'`` |
| ``headers`` | Hash of HTTP request or response headers to add as tags to the `rack.request`. Accepts `request` and `response` keys with Array values e.g. `['Last-Modified']`. Adds `http.request.headers.*` and `http.response.headers.*` tags respectively. | ``{ response: ['Content-Type', 'X-Request-ID'] }`` |

**Configuring URL quantization behavior**

```ruby
Datadog.configure do |c|
  # Default behavior: all values are quantized, fragment is removed.
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id&sort_by
  # http://example.com/path?categories[]=1&categories[]=2 --> http://example.com/path?categories[]

  # Show values for any query string parameter matching 'category_id' exactly
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id=1&sort_by
  c.use :rack, quantize: { query: { show: ['category_id'] } }

  # Show all values for all query string parameters
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id=1&sort_by=asc
  c.use :rack, quantize: { query: { show: :all } }

  # Totally exclude any query string parameter matching 'sort_by' exactly
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id
  c.use :rack, quantize: { query: { exclude: ['sort_by'] } }

  # Remove the query string entirely
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path
  c.use :rack, quantize: { query: { exclude: :all } }

  # Show URL fragments
  # http://example.com/path?category_id=1&sort_by=asc#featured --> http://example.com/path?category_id&sort_by#featured
  c.use :rack, quantize: { fragment: :show }
end
```

### Rails

The Rails integration will trace requests, database calls, templates rendering and cache read/write/delete operations. The integration makes use of the Active Support Instrumentation, listening to the Notification API so that any operation instrumented by the API is traced.

To enable the Rails auto instrumentation, create an initializer file in your ``config/initializers`` folder:

```ruby
# config/initializers/datadog-tracer.rb

Datadog.configure do |c|
  c.use :rails, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used when tracing application requests (on the `rack` level) | ``<app_name>`` (inferred from your Rails application namespace) |
| ``controller_service`` | Service name used when tracing a Rails action controller | ``<app_name>`` |
| ``cache_service`` | Cache service name used when tracing cache activity | ``<app_name>-cache`` |
| ``database_service`` | Database service name used when tracing database activity | ``<app_name>-<adapter_name>`` |
| ``exception_controller`` | Class or Module which identifies a custom exception controller class. Tracer provides improved error behavior when it can identify custom exception controllers. By default, without this option, it 'guesses' what a custom exception controller looks like. Providing this option aids this identification. | ``nil`` |
| ``distributed_tracing`` | Enables [distributed tracing](#distributed-tracing) so that this service trace is connected with a trace of another service if tracing headers are received | `false` |
| ``middleware_names`` | Enables any short-circuited middleware requests to display the middleware name as resource for the trace. | `false` |
| ``template_base_path`` | Used when the template name is parsed. If you don't store your templates in the ``views/`` folder, you may need to change this value | ``views/`` |
| ``tracer`` | A ``Datadog::Tracer`` instance used to instrument the application. Usually you don't need to set that. | ``Datadog.tracer`` |
| ``databases`` | Hash of tracer settings to use for each database connection. See [ActiveRecord](#activerecord) for more details. | ``{}`` |

### Rake

You can add instrumentation around your Rake tasks by activating the `rake` integration. Each task and its subsequent subtasks will be traced.

To activate Rake task tracing, add the following to your `Rakefile`:

```ruby
# At the top of your Rakefile:
require 'rake'
require 'ddtrace'

Datadog.configure do |c|
  c.use :rake, options
end

task :my_task do
  # Do something task work here...
end

Rake::Task['my_task'].invoke
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``enabled`` | Defines whether Rake tasks should be traced. Useful for temporarily disabling tracing. `true` or `false` | ``true`` |
| ``quantize`` | Hash containing options for quantization of task arguments. See below for more details and examples. | ``{}`` |
| ``service_name`` | Service name which the Rake task traces should be grouped under. | ``rake`` |
| ``tracer`` | A ``Datadog::Tracer`` instance used to instrument the application. Usually you don't need to set that. | ``Datadog.tracer`` |

**Configuring task quantization behavior**

```ruby
Datadog.configure do |c|
  # Given a task that accepts :one, :two, :three...
  # Invoked with 'foo', 'bar', 'baz'.

  # Default behavior: all arguments are quantized.
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> { one: '?', two: '?', three: '?' }
  c.use :rake

  # Show values for any argument matching :two exactly
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> { one: '?', two: 'bar', three: '?' }
  c.use :rake, quantize: { args: { show: [:two] } }

  # Show all values for all arguments.
  # `rake.invoke.args` tag  --> ['foo', 'bar', 'baz']
  # `rake.execute.args` tag --> { one: 'foo', two: 'bar', three: 'baz' }
  c.use :rake, quantize: { args: { show: :all } }

  # Totally exclude any argument matching :three exactly
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> { one: '?', two: '?' }
  c.use :rake, quantize: { args: { exclude: [:three] } }

  # Remove the arguments entirely
  # `rake.invoke.args` tag  --> ['?']
  # `rake.execute.args` tag --> {}
  c.use :rake, quantize: { args: { exclude: :all } }
end
```

### Redis

The Redis integration will trace simple calls as well as pipelines.

```ruby
require 'redis'
require 'ddtrace'

Datadog.configure do |c|
  c.use :redis, service_name: 'redis'
end

# now do your Redis stuff, eg:
redis = Redis.new
redis.set 'foo', 'bar' # traced!
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `redis` instrumentation | redis |

You can also set *per-instance* configuration as it follows:

```ruby
customer_cache = Redis.new
invoice_cache = Redis.new

Datadog.configure(customer_cache, service_name: 'customer-cache')
Datadog.configure(invoice_cache, service_name: invoice-cache')

customer_cache.get(...) # traced call will belong to `customer-cache` service
invoice_cache.get(...) # traced call will belong to `invoice-cache` service
```

### Resque

The Resque integration uses Resque hooks that wraps the ``perform`` method.
To add tracing to a Resque job, simply do as follows:

```ruby
require 'ddtrace'

class MyJob
  def self.perform(*args)
    # do_something
  end
end

Datadog.configure do |c|
  c.use :resque, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `resque` instrumentation | resque |
| ``workers`` | An array including all worker classes you want to trace (eg ``[MyJob]``) | ``[]`` |

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
  c.use :sequel, options
end

# Perform a query
articles = database[:articles]
articles.all
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `sequel.query` spans. | Name of database adapter (e.g. `mysql2`) |
| ``tracer`` | A ``Datadog::Tracer`` instance used to instrument the application. Usually you don't need to set that. | ``Datadog.tracer`` |

Only Ruby 2.0+ is supported.

**Configuring databases to use different settings**

If you use multiple databases with Sequel, you can give each of them different settings by configuring their respective `Sequel::Database` objects:

```ruby
sqlite_database = Sequel.sqlite
postgres_database = Sequel.connect('postgres://user:password@host:port/database_name')

# Configure each database with different service names
Datadog.configure(sqlite_database, service_name: 'my-sqlite-db')
Datadog.configure(postgres_database, service_name: 'my-postgres-db')
```

### Sidekiq

The Sidekiq integration is a server-side middleware which will trace job executions.

You can enable it through `Datadog.configure`:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.use :sidekiq, options
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `sidekiq` instrumentation | sidekiq |

### Sinatra

The Sinatra integration traces requests and template rendering.

To start using the tracing client, make sure you import ``ddtrace`` and ``ddtrace/contrib/sinatra/tracer`` after
either ``sinatra`` or ``sinatra/base``:

```ruby
require 'sinatra'
require 'ddtrace'
require 'ddtrace/contrib/sinatra/tracer'

Datadog.configure do |c|
  c.use :sinatra, options
end

get '/' do
  'Hello world!'
end
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `sinatra` instrumentation | sinatra |
| ``resource_script_names`` | Prepend resource names with script name | ``false`` |
| ``distributed_tracing`` | Enables [distributed tracing](#distributed-tracing) so that this service trace is connected with a trace of another service if tracing headers are received | `false` |
| ``tracer`` | A ``Datadog::Tracer`` instance used to instrument the application. Usually you don't need to set that. | ``Datadog.tracer`` |
| ``headers`` | Hash of HTTP request or response headers to add as tags to the `sinatra.request`. Accepts `request` and `response` keys with Array values e.g. `['Last-Modified']`. Adds `http.request.headers.*` and `http.response.headers.*` tags respectively. | ``{ response: ['Content-Type', 'X-Request-ID'] }`` |

### Sucker Punch

The `sucker_punch` integration traces all scheduled jobs:

```ruby
require 'ddtrace'

Datadog.configure do |c|
  c.use :sucker_punch, options
end

# the execution of this job is traced
LogJob.perform_async('login')
```

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Description | Default |
| --- | --- | --- |
| ``service_name`` | Service name used for `sucker_punch` instrumentation | sucker_punch |

## Advanced configuration

### Tracer settings

To change the default behavior of the Datadog tracer, you can provide custom options inside the `Datadog.configure` block as in:

```ruby
# config/initializers/datadog-tracer.rb

Datadog.configure do |c|
  c.tracer option_name: option_value, ...
end
```

Available options are:

 - ``enabled``: defines if the ``tracer`` is enabled or not. If set to ``false`` the code could be still instrumented
  because of other settings, but no spans are sent to the local trace agent.
 - ``debug``: set to true to enable debug logging.
 - ``hostname``: set the hostname of the trace agent.
 - ``port``: set the port the trace agent is listening on.
 - ``env``: set the environment. Rails users may set it to ``Rails.env`` to use their application settings.
 - ``tags``: set global tags that should be applied to all spans. Defaults to an empty hash
 - ``log``: defines a custom logger.
 - ``partial_flush``: set to ``true`` to enable partial trace flushing (for long running traces.) Disabled by default. *Experimental.*

#### Custom logging

By default, all logs are processed by the default Ruby logger. When using Rails, you should see the messages in your application log file.

Datadog client log messages are marked with ``[ddtrace]`` so you should be able to isolate them from other messages.

Additionally, it is possible to override the default logger and replace it by a custom one. This is done using the ``log`` attribute of the tracer.

```ruby
f = File.new("my-custom.log", "w+")           # Log messages should go there
Datadog.configure do |c|
  c.tracer log: Logger.new(f)                 # Overriding the default tracer
end

Datadog::Tracer.log.info { "this is typically called by tracing code" }
```

### Environment and tags

By default, the trace agent (not this library, but the program running in the background collecting data from various clients) uses the tags set in the agent config file, see our [environments tutorial](https://app.datadoghq.com/apm/docs/tutorials/environments) for details.

These values can be overridden at the tracer level:

```ruby
Datadog.configure do |c|
  c.tracer tags: { 'env' => 'prod' }
end
```

This enables you to set this value on a per tracer basis, so you can have for example several applications reporting for different environments on the same host.

Ultimately, tags can be set per span, but `env` should typically be the same for all spans belonging to a given trace.

### Sampling

`ddtrace` can perform trace sampling. While the trace agent already samples traces to reduce bandwidth usage, client sampling reduces performance overhead.

`Datadog::RateSampler` samples a ratio of the traces. For example:

```ruby
# Sample rate is between 0 (nothing sampled) to 1 (everything sampled).
sampler = Datadog::RateSampler.new(0.5) # sample 50% of the traces
Datadog.configure do |c|
  c.tracer sampler: sampler
end
```

#### Priority sampling

Priority sampling consists in deciding if a trace will be kept by using a priority attribute that will be propagated for distributed traces. Its value gives indication to the Agent and to the backend on how important the trace is.

The sampler can set the priority to the following values:

 - `Datadog::Ext::Priority::AUTO_REJECT`: the sampler automatically decided to reject the trace.
 - `Datadog::Ext::Priority::AUTO_KEEP`: the sampler automatically decided to keep the trace.

For now, priority sampling is disabled by default. Enabling it ensures that your sampled distributed traces will be complete. To enable the priority sampling:

```ruby
Datadog.configure do |c|
  c.tracer priority_sampling: true
end
```

Once enabled, the sampler will automatically assign a priority of 0 or 1 to traces, depending on their service and volume.

You can also set this priority manually to either drop a non-interesting trace or to keep an important one. For that, set the `context#sampling_priority` to:

 - `Datadog::Ext::Priority::USER_REJECT`: the user asked to reject the trace.
 - `Datadog::Ext::Priority::USER_KEEP`: the user asked to keep the trace.

When not using [distributed tracing](#distributed-tracing), you may change the priority at any time, as long as the trace is not finished yet. But it has to be done before any context propagation (fork, RPC calls) to be effective in a distributed context. Changing the priority after context has been propagated causes different parts of a distributed trace to use different priorities. Some parts might be kept, some parts might be rejected, and this can cause the trace to be partially stored and remain incomplete.

If you change the priority, we recommend you do it as soon as possible, when the root span has just been created.

```ruby
# Indicate to reject the trace
span.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT

# Indicate to keep the trace
span.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP
```

### Distributed Tracing

Distributed tracing allows traces to be propagated across multiple instrumented applications, so that a request can be presented as a single trace, rather than a separate trace per service.

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
  | Service B HTTP Request:
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

**Activating distributed tracing for integrations**

Many integrations included in `ddtrace` support distributed tracing. Distributed tracing is disabled by default, but can be activated via configuration settings.

- If your application receives requests from services with distributed tracing activated, you must activate distributed tracing on the integrations that handle these requests (e.g. Rails)
- If your application send requests to services with distributed tracing activated, you must activate distributed tracing on the integrations that send these requests (e.g. Faraday)
- If your application both sends and receives requests implementing distributed tracing, it must activate all integrations which handle these requests.

For more details on how to activate distributed tracing for integrations, see their documentation:

- [Excon](#excon)
- [Faraday](#faraday)
- [Net/HTTP](#nethttp)
- [Rack](#rack)
- [Rails](#rails)
- [Sinatra](#sinatra)

**Using the HTTP propagator**

To make the process of propagating this metadata easier, you can use the `Datadog::HTTPPropagator` module.

On the client:

```ruby
Datadog.tracer.trace('web.call') do |span|
  # Inject span context into headers (`env` must be a Hash)
  Datadog::HTTPPropagator.inject!(span.context, env)
end
```

On the server:

```ruby
Datadog.tracer.trace('web.work') do |span|
  # Build a context from headers (`env` must be a Hash)
  context = HTTPPropagator.extract(request.env)
  Datadog.tracer.provider.context = context if context.trace_id
end
```

### HTTP request queuing

Traces that originate from HTTP requests can be configured to include the time spent in a frontend web server or load balancer queue, before the request reaches the Ruby application.

This functionality is **experimental** and deactivated by default.

To activate this feature, you must add a ``X-Request-Start`` or ``X-Queue-Start`` header from your web server (i.e. Nginx). The following is an Nginx configuration example:

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

Then you must enable the request queuing feature in the integration handling the request.

For Rack based applications, see the [documentation](#rack) for details for enabling this feature.

### Processing Pipeline

Some applications might require that traces be altered or filtered out before they are sent upstream. The processing pipeline allows users to create *processors* to define such behavior.

Processors can be any object that responds to `#call` accepting `trace` as an argument (which is an `Array` of `Datadog::Span`s.)

For example:

```ruby
lambda_processor = ->(trace) do
  # Processing logic...
  trace
end

class MyCustomProcessor
  def call(trace)
    # Processing logic...
    trace
  end
end
custom_processor = MyFancyProcessor.new
```

`#call` blocks of processors *must* return the `trace` object; this return value will be passed to the next processor in the pipeline.

These processors must then be added to the pipeline via `Datadog::Pipeline.before_flush`:

```ruby
Datadog::Pipeline.before_flush(lambda_processor, custom_processor)
```

You can also define processors using the short-hand block syntax for `Datadog::Pipeline.before_flush`:

```ruby
Datadog::Pipeline.before_flush do |trace|
  trace.delete_if { |span| span.name =~ /forbidden/ }
end
```

#### Filtering

You can use the `Datadog::Pipeline::SpanFilter` processor to remove spans, when the block evaluates as truthy:

```ruby
Datadog::Pipeline.before_flush(
  # Remove spans that match a particular resource
  Datadog::Pipeline::SpanFilter.new { |span| span.resource =~ /PingController/ },
  # Remove spans that are trafficked to localhost
  Datadog::Pipeline::SpanFilter.new { |span| span.get_tag('host') == 'localhost' }
)
```

#### Processing

You can use the `Datadog::Pipeline::SpanProcessor` processor to modify spans:

```ruby
Datadog::Pipeline.before_flush(
  # Strip matching text from the resource field
  Datadog::Pipeline::SpanProcessor.new { |span| span.resource.gsub!(/password=.*/, '') }
)
```
