# Datadog Trace Client

``ddtrace`` is Datadog’s tracing client for Ruby. It is used to trace requests as they flow across web servers,
databases and microservices so that developers have great visiblity into bottlenecks and troublesome requests.

## Install the gem

Install the tracing client, adding the following gem in your ``Gemfile``:

    source 'https://rubygems.org'

    # tracing gem
    gem 'ddtrace'

If you're not using ``Bundler`` to manage your dependencies, you can install ``ddtrace`` with:

    gem install ddtrace

We strongly suggest pinning the version of the library you deploy.

## Quickstart

The easiest way to get started with the tracing client is to instrument your web application.
All configuration is done through ``Datadog.configure`` method. As an
example, below is a setup that enables auto instrumentation for Rails, Redis and
Grape, and sets a custom endpoint for the trace agent:

    # config/initializers/datadog-tracer.rb

    Datadog.configure do |c|
      c.tracer hostname: 'trace-agent.local'
      c.use :rails
      c.use :grape
      c.use :redis, service_name: 'cache'
    end

For further details and options, check our integrations list.

## Available Integrations

* [Ruby on Rails](#Ruby_on_Rails)
* [Sinatra](#Sinatra)
* [Rack](#Rack)
* [Grape](#Grape)
* [Active Record](#Active_Record)
* [Elastic Search](#Elastic_Search)
* [MongoDB](#MongoDB)
* [Sidekiq](#Sidekiq)
* [Resque](#Resque)
* [SuckerPunch](#SuckerPunch)
* [Net/HTTP](#Net_HTTP)
* [Faraday](#Faraday)
* [Dalli](#Dalli)
* [Redis](#Redis)

## Web Frameworks

### Ruby on Rails

The Rails integration will trace requests, database calls, templates rendering and cache read/write/delete
operations. The integration makes use of the Active Support Instrumentation, listening to the Notification API
so that any operation instrumented by the API is traced.

To enable the Rails auto instrumentation, create an initializer file in your ``config/`` folder:

    # config/initializers/datadog-tracer.rb

    Datadog.configure do |c|
      c.use :rails
    end

To use service names other than the default ones, you might provide custom options as:

    # config/initializers/datadog-tracer.rb

    Datadog.configure do |c|
      c.use :rails, option_name: option_value, ...
    end

Available options for the `rails` integration are:

* ``service_name``: set the service name used when tracing application requests (on the `rack` level). Defaults to ``<app_name>``, where `<app_name>` is automatically inferred from your Rails application namespace;
* ``controller_service``: set the service name used when tracing a Rails action controller. Defaults to ``<app_name>-controller``
* ``cache_service``: set the cache service name used when tracing cache activity. Defaults to ``<app_name>-cache``
* ``database_service``: set the database service name used when tracing database activity. Defaults to the
  current adapter name, so if you're using PostgreSQL it will be ``<app_name>-postgres``.
* ``distributed_tracing``: enable [distributed tracing](#Distributed_Tracing) so that this service trace is
  connected with a trace of another service if tracing headers are sent
* ``template_base_path``: used when the template name is parsed in the auto instrumented code. If you don't store
  your templates in the ``views/`` folder, you may need to change this value
* ``tracer``: is the global tracer used by the tracing application. Usually you don't need to change that value
  unless you're already using a different initialized ``tracer`` somewhere else

### Sinatra

The Sinatra integration traces requests and template rendering.

To start using the tracing client, make sure you import ``ddtrace`` and ``ddtrace/contrib/sinatra/tracer`` after
either ``sinatra`` or ``sinatra/base``:

    require 'sinatra'
    require 'ddtrace'
    require 'ddtrace/contrib/sinatra/tracer'

    Datadog.configure do |c|
      c.use :sinatra, service_name: 'my-app'
    end

    get '/' do
      'Hello world!'
    end

The tracing extension will be automatically activated.

### Rack

The Rack integration provides a middleware that traces all requests before they reach the underlying framework
or application. It responds to the Rack minimal interface, providing reasonable values that can be
retrieved at the Rack level.
To start using the middleware in your generic Rack application, add it to your ``config.ru``:

    # config.ru example
    require 'ddtrace'

    Datadog.configure { |c| c.use(:rack) }

    use Datadog::Contrib::Rack::TraceMiddleware

    app = proc do |env|
      [ 200, {'Content-Type' => 'text/plain'}, "OK" ]
    end

    run app

The Rack middleware can be configured using the global configuration object:

    # config.ru example
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :rack, service_name: 'api-intake', distributed_tracing: true
    end

    app = proc do |env|
      [ 200, {'Content-Type' => 'text/plain'}, "OK" ]
    end

In the example above, we've activated the Distributed Tracing flag, please
see [distributed tracing](#Distributed_Tracing) for more details.

## Other libraries

### Grape

The Grape integration adds the instrumentation to Grape endpoints and filters. This integration can work side by side
with other integrations like Rack and Rails. To activate your integration, use the ``patch_module`` function before
defining your Grape application:

    # api.rb
    require 'grape'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :grape
    end

    # then define your application
    class RackTestingAPI < Grape::API
      desc 'main endpoint'
      get :success do
        'Hello world!'
      end
    end

### Active Record

Most of the time, Active Record is set up as part of a web framework (Rails, Sinatra...)
however it can be set up alone:

    require 'tmpdir'
    require 'sqlite3'
    require 'active_record'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :active_record
    end

    Dir::Tmpname.create(['test', '.sqlite']) do |db|
      conn = ActiveRecord::Base.establish_connection(adapter: 'sqlite3',
                                                     database: db)
      conn.connection.execute('SELECT 42') # traced!
    end

### Elastic Search

The Elasticsearch integration will trace any call to ``perform_request``
in the ``Client`` object:

    require 'elasticsearch/transport'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :elasticsearch
    end

    # now do your Elastic Search stuff, eg:
    client = Elasticsearch::Client.new url: 'http://127.0.0.1:9200'
    response = client.perform_request 'GET', '_cluster/health'

Note that if you enable both Elasticsearch and Net/HTTP integrations then
for each call, two spans are created, one for Elasctisearch and one for Net/HTTP.
This typically happens if you call ``patch_all`` to enable all integrations by default.

### MongoDB

The integration traces any `Command` that is sent from the
[MongoDB Ruby Driver](https://github.com/mongodb/mongo-ruby-driver) to a MongoDB cluster.
By extension, Object Document Mappers (ODM) such as Mongoid are automatically instrumented
if they use the official Ruby driver. To activate the integration, simply:

    require 'mongo'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :mongo, service_name: 'mongodb'
    end

    # now create a MongoDB client and use it as usual:
    client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'artists')
    collection = client[:people]
    collection.insert_one({ name: 'Steve' })

    # In case you want to override the global configuration for a certain client instance
    Datadog.configure(client) do |c|
      c.service_name = 'mongodb-primary'
    end

### Net/HTTP

The Net/HTTP integration will trace any HTTP call using the standard lib
Net::HTTP module.

    require 'net/http'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :http
    end

    Net::HTTP.start('127.0.0.1', 8080) do |http|
      request = Net::HTTP::Get.new '/index'
      response = http.request request
    end

    content = Net::HTTP.get(URI('http://127.0.0.1/index.html'))

Experimental distributed tracing support is available for this library.
By default, this is disabled. You need to enable it, either on a per-connection basis,
by setting the ``:distributed_tracing`` through `Datadog.configure`

    require 'net/http'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :http
    end

    client = Net::HTTP.new(host, port)
    Datadog.configure(client).config = { distributed_tracing: true }
    response = client.get('foo') # trace and send 'x-datadog-trace-id' and 'x-datadog-parent-id'

Or, by enabling distributed tracing for all HTTP calls:

    require 'net/http'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :http, distributed_tracing: true
    end

See [distributed tracing](#Distributed_Tracing) for details.

### Faraday

The `faraday` integration is available through the `ddtrace` middleware:

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

Where `options` is an optional `Hash` that accepts the following parameters:

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `service_name` | String | Global service name (default: `faraday`) | Service name for this specific connection object. |
| `split_by_domain` | Boolean | `false` | Uses the request domain as the service name when set to `true`. |
| `distributed_tracing` | Boolean | `false` | Propagates tracing context along the HTTP request when set to `true`. |
| `error_handler` | Callable | ``5xx`` evaluated as errors | A callable object that receives a single argument – the request environment. If it evaluates to a *truthy* value, the trace span is marked as an error. |

### AWS

The AWS integration will trace every interaction (e.g. API calls) with AWS
services (S3, ElastiCache etc.).

    require 'aws-sdk'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :aws, service_name: 'aws'
    end

    Aws::S3::Client.new.list_buckets # traced call

### Dalli

Dalli integration will trace all calls to your ``memcached`` server:

    require 'dalli'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :dalli, service_name: 'dalli'
    end

    client = Dalli::Client.new('localhost:11211', options)
    client.set('abc', 123)

### Redis

The Redis integration will trace simple calls as well as pipelines.

    require 'redis'
    require 'ddtrace'

    Datadog.configure do |c|
      c.use :dalli, service_name: 'redis'
    end

    # now do your Redis stuff, eg:
    redis = Redis.new
    redis.set 'foo', 'bar' # traced!

### Sidekiq

The Sidekiq integration is a server-side middleware which will trace job
executions. You can enable it through `Datadog.configure`:

    require 'ddtrace'

    Datadog.configure do |c|
      c.use :sidekiq, service_name: 'my-sidekiq'
    end

### Resque

The Resque integration uses Resque hooks that wraps the ``perform`` method.
To add tracing to a Resque job, simply do as follows:

    require 'ddtrace'

    class MyJob
      def self.perform(*args)
        # do_something
      end
    end

    Datadog.configure do |c|
      c.use :resque, service_name: 'resque', workers: [MyJob]
    end

### SuckerPunch

The `sucker_punch` integration traces all scheduled jobs:

    require 'ddtrace'

    Datadog.configure do |c|
      c.use :sucker_punch, service_name: 'sucker_punch'
    end

    # the execution of this job is traced
    LogJob.perform_async('login')

## Advanced usage

### Configure the tracer

To change the default behavior of the Datadog tracer, you can provide custom options inside the `Datadog.configure` block as in:

    # config/initializers/datadog-tracer.rb

    Datadog.configure do |c|
      c.tracer option_name: option_value, ...
    end

Available options are:

* ``enabled``: defines if the ``tracer`` is enabled or not. If set to ``false`` the code could be still instrumented
  because of other settings, but no spans are sent to the local trace agent.
* ``debug``: set to true to enable debug logging.
* ``hostname``: set the hostname of the trace agent.
* ``port``: set the port the trace agent is listening on.
* ``env``: set the environment. Rails users may set it to ``Rails.env`` to use their application settings.
* ``tags``: set global tags that should be applied to all spans. Defaults to an empty hash

### Manual Instrumentation

If you aren't using a supported framework instrumentation, you may want to to manually instrument your code.
Adding tracing to your code is very simple. As an example, let’s imagine we have a web server and we want
to trace requests to the home page:

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

        # trace the activerecord call
        tracer.trace('posts.fetch') do
          @posts = Posts.order(created_at: :desc).limit(10)
        end

        # add some attributes and metrics
        span.set_tag('http.method', request.request_method)
        span.set_tag('posts.count', @posts.length)

        # trace the template rendering
        tracer.trace('template.render') do
          erb :index
        end

        # trace using start_span (fine-grain control, requires explicit call to finish)
        child = tracer.start_span('child', child_of: span)
        # do something
        child.finish
      end
    end

### Ad-hoc configuration

Certain integrations such as `Redis`, `Elasticsearch` and `net/http` may have
different configuration parameters for each of its instances (generally a
connection object).

For cases like this, you can provide the targeted instance to
`Datadog.configure` method and set the following attributes:

* ``service_name``: service, you should typically set some meaningful value for this.
* ``app``: application name
* ``tags``: optional tags
* ``app_type``: application type
* ``name``: span name
* ``tracer``: the tracer object used for tracing

#### Example

    require 'redis'
    require 'ddtrace'

    # Enable tracing globally for redis
    Datadog.configure { |c| c.use(:redis) }

    customer_cache = Redis.new
    invoice_cache = Redis.new

    Datadog.configure(customer_cache) do |c|
      c.service_name = 'customer-cache'
    end

    Datadog.configure(invoice_cache) do |c|
      c.service_name = invoice-cache'
    end

    customer_cache.get(...) # traced call will belong to `customer-cache` service
    invoice_cache.get(...) # traced call will belong to `invoice-cache` service

### Debug Mode

If you need to check locally what traces and spans are sent after each traced block, you can enable
a global debug mode for all tracers so that every time a trace is ready to be sent, the content will be
printed in the +STDOUT+. To enable the debug logging, add this code anywhere before using the tracer
for the first time:

    require 'ddtrace'
    require 'sinatra'
    require 'active_record'

    Datadog.configure { |c| c.tracer(debug: true) }

    # use the tracer as usual
    tracer = Datadog.tracer

    get '/' do
      tracer.trace('web.request') do |span|
        # ...
      end
    end

Remember that the debug mode may affect your application performance and so it must not be used
in a production environment.

### Using a custom logger

By default, all logs are processed by the default Ruby logger.
Typically, when using Rails, you should see the messages in your application log file.
Datadog client log messages are marked with ``[ddtrace]`` so you should be able
to isolate them from other messages.

Additionally, it is possible to override the default logger and replace it by a
custom one. This is done using the ``log`` attribute of the tracer.

    f = File.new("my-custom.log", "w+")           # Log messages should go there
    Datadog::Tracer.log = Logger.new(f)           # Overriding the default tracer
    Datadog::Tracer.log.info { "this is typically called by tracing code" }

### Environment and tags

By default, the trace agent (not this library, but the program running in
the background collecting data from various clients) uses the tags
set in the agent config file, see our
[environments tutorial](https://app.datadoghq.com/apm/docs/tutorials/environments) for details.

These values can be overridden at the tracer level:

    Datadog.configure do |c|
      c.tracer tags: { 'env' => 'prod' }
    end

This enables you to set this value on a per tracer basis, so you can have
for example several applications reporting for different environments on the same host.

Ultimately, tags can be set per span, but `env` should typically be the same
for all spans belonging to a given trace.

### Sampling

`ddtrace` can perform trace sampling. While the trace agent already samples
traces to reduce bandwidth usage, client sampling reduces performance
overhead.

`Datadog::RateSampler` samples a ratio of the traces. For example:

    # Sample rate is between 0 (nothing sampled) to 1 (everything sampled).
    sampler = Datadog::RateSampler.new(0.5) # sample 50% of the traces
    Datadog.configure do |c|
      c.tracer sampler: sampler
    end

#### Priority sampling

Priority sampling consists in deciding if a trace will be kept by using a priority attribute that will be propagated for distributed traces. Its value gives indication to the Agent and to the backend on how important the trace is.

The sampler can set the priority to the following values:

* `Datadog::Ext::Priority::AUTO_REJECT`: the sampler automatically decided to reject the trace.
* `Datadog::Ext::Priority::AUTO_KEEP`: the sampler automatically decided to keep the trace.

For now, priority sampling is disabled by default. Enabling it ensures that your sampled distributed traces will be complete. To enable the priority sampling:

```rb
Datadog.tracer.configure(priority_sampling: true)
```

Once enabled, the sampler will automatically assign a priority of 0 or 1 to traces, depending on their service and volume.

You can also set this priority manually to either drop a non-interesting trace or to keep an important one. For that, set the `context#sampling_priority` to:

* `Datadog::Ext::Priority::USER_REJECT`: the user asked to reject the trace.
* `Datadog::Ext::Priority::USER_KEEP`: the user asked to keep the trace.

When not using [distributed tracing](#Distributed_Tracing), you may change the priority at any time,
as long as the trace is not finished yet.
But it has to be done before any context propagation (fork, RPC calls) to be effective in a distributed context.
Changing the priority after context has been propagated causes different parts of a distributed trace
to use different priorities. Some parts might be kept, some parts might be rejected,
and this can cause the trace to be partially stored and remain incomplete.

If you change the priority, we recommend you do it as soon as possible, when the root span has just been created.

```rb
# Indicate to reject the trace
span.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT

# Indicate to keep the trace
span.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP
```

### Distributed Tracing

To trace requests across hosts, the spans on the secondary hosts must be linked together by setting ``trace_id`` and ``parent_id``:

    def request_on_secondary_host(parent_trace_id, parent_span_id)
        tracer.trace('web.request') do |span|
           span.parent_id = parent_span_id
           span.trace_id = parent_trace_id

           # perform user code
        end
    end

Users can pass along the ``parent_trace_id`` and ``parent_span_id`` via whatever method best matches the RPC framework.

Below is an example using Net/HTTP and Sinatra, where we bypass the integrations to demo how distributed tracing works.

On the client:

    require 'net/http'
    require 'ddtrace'

    uri = URI('http://localhost:4567/')

    Datadog.tracer.trace('web.call') do |span|
      req = Net::HTTP::Get.new(uri)
      req['x-datadog-trace-id'] = span.trace_id.to_s
      req['x-datadog-parent-id'] = span.span_id.to_s

      response = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(req)
      end

      puts response.body
    end

On the server:

    require 'sinatra'
    require 'ddtrace'

    get '/' do
      parent_trace_id = request.env['HTTP_X_DATADOG_TRACE_ID']
      parent_span_id = request.env['HTTP_X_DATADOG_PARENT_ID']

      Datadog.tracer.trace('web.work') do |span|
         if parent_trace_id && parent_span_id
           span.trace_id = parent_trace_id.to_i
           span.parent_id = parent_span_id.to_i
         end

        'Hello world!'
      end
    end

[Rack](#Rack) and [Net/HTTP](#Net_HTTP) have experimental support for this, they
can send and receive these headers automatically and tie spans together automatically,
provided you pass a ``:distributed_tracing`` option set to ``true``.

This is disabled by default.

### Processing Pipeline

Sometimes it might be interesting to intercept `Span` objects before they get
sent upstream.  To achieve that, you can hook custom *processors* into the
pipeline using the method `Datadog::Pipeline.before_flush`:

    Datadog::Pipeline.before_flush(
      # filter the Span if the given block evaluates true
      Datadog::Pipeline::SpanFilter.new { |span| span.resource =~ /PingController/ },
      Datadog::Pipeline::SpanFilter.new { |span| span.get_tag('host') == 'localhost' }

      # alter the Span updating fields or tags
      Datadog::Pipeline::SpanProcessor.new { |span| span.resource.gsub!(/password=.*/, '') }
    )

For more information, please refer to this [link](https://github.com/DataDog/dd-trace-rb/pull/214).

### Troubleshooting

#### Logs

Your application log should contain informations and report problems
such as agent not being up and running. All logs generated by this
library should contain ``[ddtrace]``. Also see [how to use a custom logger](#Using_a_custom_logger)
to redirect these messages elsewhere.

The [Datadog Trace Agent](https://github.com/DataDog/datadog-trace-agent)
should by default be listening for traces on port 8126.

#### Hello World

Sometimes, setting up a complete application is complex, so in doubt,
try the small program below, which should be able to report traces
for a ``tracegen`` service:

    require 'ddtrace'

    loop do
        Datadog.tracer.trace('hello-world') do |span|
            span.service = 'tracegen'
            span.resource = 'ruby'
            sleep 1
        end
    end

### Supported Versions

#### Ruby interpreters

The Datadog Trace Client has been tested with the following Ruby versions:

* Ruby MRI 1.9.1 (experimental)
* Ruby MRI 1.9.3
* Ruby MRI 2.0
* Ruby MRI 2.1
* Ruby MRI 2.2
* Ruby MRI 2.3
* Ruby MRI 2.4
* JRuby 9.1.5 (experimental)

Other versions aren't yet officially supported.

#### Ruby on Rails versions

The supported versions are:

* Rails 3.2 (MRI interpreter, JRuby is experimental)
* Rails 4.2 (MRI interpreter, JRuby is experimental)
* Rails 5.0 (MRI interpreter)

The currently supported web server are:
* Puma 2.16+ and 3.6+
* Unicorn 4.8+ and 5.1+
* Passenger 5.0+

#### Sinatra versions

Currently we are supporting Sinatra >= 1.4.0.

#### Sidekiq versions

Currently we are supporting Sidekiq >= 4.0.0.

### Terminology

If you need more context about the terminology used in the APM, take a look at the [official documentation](https://docs.datadoghq.com/tracing/terminology/).
