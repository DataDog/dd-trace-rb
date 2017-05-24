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

The easiest way to get started with the tracing client is to instrument your web application. ``ddtrace`` gem
provides auto instrumentation for the following web frameworks and libraries:

* [Ruby on Rails](#Ruby_on_Rails)
* [Sidekiq](#Sidekiq)
* [Sinatra](#Sinatra)
* [Rack](#Rack)
* [Grape](#Grape)
* [Active Record](#Active_Record)
* [Elastic Search](#Elastic_Search)
* [Net/HTTP](#Net_HTTP)
* [Redis](#Redis)

## Web Frameworks

### Ruby on Rails

The Rails integration will trace requests, database calls, templates rendering and cache read/write/delete
operations. The integration makes use of the Active Support Instrumentation, listening to the Notification API
so that any operation instrumented by the API is traced.

To enable the Rails auto instrumentation, create an initializer file in your ``config/`` folder:

    # config/initializers/datadog-tracer.rb

    Rails.configuration.datadog_trace = {
      auto_instrument: true,
      auto_instrument_redis: true,
      default_service: 'my-rails-app'
    }

If you're using Rails 3 or higher, your application will be listed as ``my-rails-app`` in your service list.
To integrate Rails instrumentation with third-party libraries such as Grape, please check the available settings below.

#### Configure the tracer with initializers

All tracing settings are namespaced under the ``Rails.configuration.datadog_tracer`` hash. To change the default behavior
of the Datadog tracer, you can override the following defaults:

    # config/initializers/datadog-tracer.rb

    Rails.configuration.datadog_trace = {
      enabled: true,
      auto_instrument: false,
      auto_instrument_redis: false,
      auto_instrument_grape: false,
      default_service: 'rails-app',
      default_controller_service: 'rails-controller',
      default_cache_service: 'rails-cache',
      default_database_service: 'postgresql',
      template_base_path: 'views/',
      tracer: Datadog.tracer,
      debug: false,
      trace_agent_hostname: 'localhost',
      trace_agent_port: 8126,
      env: nil,
      tags: {}
    }

Available settings are:

* ``enabled``: defines if the ``tracer`` is enabled or not. If set to ``false`` the code could be still instrumented
  because of other settings, but no spans are sent to the local trace agent.
* ``auto_instrument``: if set to +true+ the code will be automatically instrumented. You may change this value
  with a condition, to enable the auto-instrumentation only for particular environments (production, staging, etc...).
* ``auto_instrument_redis``: if set to ``true`` Redis calls will be traced as such. Calls to Redis cache may be
  still instrumented but you will not have the detail of low-level Redis calls.
* ``auto_instrument_grape``: if set to ``true`` and you're using a Grape application, all calls to your endpoints are
  traced, including filters execution.
* ``default_service``: set the service name used when tracing application requests. Defaults to ``rails-app``
* ``default_controller_service``: set the service name used when tracing a Rails action controller. Defaults to ``rails-controller``
* ``default_cache_service``: set the cache service name used when tracing cache activity. Defaults to ``rails-cache``
* ``default_database_service``: set the database service name used when tracing database activity. Defaults to the
  current adapter name, so if you're using PostgreSQL it will be ``postgres``.
* ``default_grape_service``: set the service name used when tracing a Grape application mounted in your Rails router.
  Defaults to ``grape``
* ``template_base_path``: used when the template name is parsed in the auto instrumented code. If you don't store
  your templates in the ``views/`` folder, you may need to change this value
* ``tracer``: is the global tracer used by the tracing application. Usually you don't need to change that value
  unless you're already using a different initialized ``tracer`` somewhere else
* ``debug``: set to true to enable debug logging.
* ``trace_agent_hostname``: set the hostname of the trace agent.
* ``trace_agent_port``: set the port the trace agent is listening on.
* ``env``: set the environment. Rails users may set it to ``Rails.env`` to use their application settings.
* ``tags``: set global tags that should be applied to all spans. Defaults to an empty hash

### Sinatra

The Sinatra integration traces requests and template rendering. The integration is based on the
``Datadog::Contrib::Sinatra::Tracer`` extension.

To start using the tracing client, make sure you import ``ddtrace`` and ``ddtrace/contrib/sinatra/tracer`` after
either ``sinatra`` or ``sinatra/base``:

    require 'sinatra'
    require 'ddtrace'
    require 'ddtrace/contrib/sinatra/tracer'

    get '/' do
      'Hello world!'
    end

The tracing extension will be automatically activated.

#### Configure the tracer

To modify the default configuration, use the ``settings.datadog_tracer.configure`` method. For example,
to change the default service name and activate the debug mode:

    configure do
      settings.datadog_tracer.configure default_service: 'my-app', debug: true
    end

Available settings are:

* ``enabled``: define if the ``tracer`` is enabled or not. If set to ``false``, the code is still instrumented
  but no spans are sent to the local trace agent.
* ``default_service``: set the service name used when tracing application requests. Defaults to ``sinatra``
* ``tracer``: set the tracer to use. Usually you don't need to change that value
  unless you're already using a different initialized tracer somewhere else
* ``debug``: set to ``true`` to enable debug logging.
* ``trace_agent_hostname``: set the hostname of the trace agent.
* ``trace_agent_port``: set the port the trace agent is listening on.

### Rack

The Rack integration provides a middleware that traces all requests before they reach the underlying framework
or application. It responds to the Rack minimal interface, providing reasonable values that can be
retrieved at the Rack level.
To start using the middleware in your generic Rack application, add it to your ``config.ru``:

    # config.ru example
    use Datadog::Contrib::Rack::TraceMiddleware

    app = proc do |env|
      [ 200, {'Content-Type' => 'text/plain'}, "OK" ]
    end

    run app

#### Configure the tracer

To modify the default middleware configuration, you can use middleware options as follows:

    # config.ru example
    use Datadog::Contrib::Rack::TraceMiddleware, default_service: 'rack-stack'

    app = proc do |env|
      [ 200, {'Content-Type' => 'text/plain'}, "OK" ]
    end

    run app

Available settings are:

* ``tracer`` (default: ``Datadog.tracer``): set the tracer to use. Usually you don't need to change that value
  unless you're already using a different initialized tracer somewhere else. If you need to change some
  configurations such as the ``hostname``, use the [Tracer#configure](Datadog/Tracer.html#configure-instance_method)
  method before adding the middleware
* ``default_service`` (default: ``rack``): set the service name used when the Rack request is traced

## Other libraries

### Grape

The Grape integration adds the instrumentation to Grape endpoints and filters. This integration can work side by side
with other integrations like Rack and Rails. To activate your integration, use the ``patch_module`` function before
defining your Grape application:

    # api.rb
    require 'grape'
    require 'ddtrace'

    Datadog::Monkey.patch_module(:grape)

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

    Datadog::Monkey.patch_module(:active_record) # explicitly patch it

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

    Datadog::Monkey.patch_module(:elasticsearch) # explicitly patch it

    # now do your Elastic Search stuff, eg:
    client = Elasticsearch::Client.new url: 'http://127.0.0.1:9200'
    response = client.perform_request 'GET', '_cluster/health'

Note that if you enable both Elasticsearch and Net/HTTP integrations then
for each call, two spans are created, one for Elasctisearch and one for Net/HTTP.
This typically happens if you call ``patch_all`` to enable all integrations by default.

### Net/HTTP

The Net/HTTP integration will trace any HTTP call using the standard lib
Net::HTTP module.

    require 'net/http'
    require 'ddtrace'

    Datadog::Monkey.patch_module(:http) # explicitly patch it

    Net::HTTP.start('127.0.0.1', 8080) do |http|
      request = Net::HTTP::Get.new '/index'
      response = http.request request
    end

    content = Net::HTTP.get(URI('http://127.0.0.1/index.html'))

### Redis

The Redis integration will trace simple calls as well as pipelines.

    require 'redis'
    require 'ddtrace'

    Datadog::Monkey.patch_module(:redis) # explicitly patch it

    # now do your Redis stuff, eg:
    redis = Redis.new
    redis.set 'foo', 'bar' # traced!

### Sidekiq

The Sidekiq integration is a server-side middleware which will trace job
executions. It can be added as any other Sidekiq middleware:

    require 'sidekiq'
    require 'ddtrace'
    require 'ddtrace/contrib/sidekiq/tracer'

    Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        chain.add(Datadog::Contrib::Sidekiq::Tracer)
      end
    end

#### Configure the tracer middleware

To modify the default configuration, simply pass arguments to the middleware.
For example, to change the default service name:

    Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        chain.add(
          Datadog::Contrib::Sidekiq::Tracer,
          sidekiq_service: 'sidekiq-notifications'
        )
      end
    end

Available settings are:

* ``enabled``: define if the ``tracer`` is enabled or not. If set to
  ``false``, the code is still instrumented but no spans are sent to the local
  trace agent.
* ``sidekiq_service``: set the service name used when tracing application
  requests. Defaults to ``sidekiq``.
* ``tracer``: set the tracer to use. Usually you don't need to change that
  value unless you're already using a different initialized tracer somewhere
  else.
* ``debug``: set to ``true`` to enable debug logging.
* ``trace_agent_hostname``: set the hostname of the trace agent.
* ``trace_agent_port``: set the port the trace agent is listening on.

If you're using Sidekiq along with [Ruby on Rails](#label-Ruby+on+Rails) auto-instrumentation,
the Sidekiq middleware will re-use the Rails configuration defined in the initializer file before
giving precedence to the middleware settings. Inherited configurations are:

* ``enabled``
* ``tracer``
* ``debug``
* ``trace_agent_hostname``
* ``trace_agent_port``

## Advanced usage

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
        span.set_metric('posts.count', len(@posts))

        # trace the template rendering
        tracer.trace('template.render') do
          erb :index
        end
      end
    end

### Patching methods

Integrations such as Redis or Elasticsearch use monkey patching.

The available methods are:

* ``autopatch_modules``: returns a hash of all modules available for monkey patching,
  the key is the name of the module and the value ``true`` or ``false``. If it is ``true``,
  a call to ``patch_all`` will enable the module, if it is ``false``, it will do nothing.
* ``patch_all``: patches all modules which are supported. Make sure all the necessary
  calls to ``require`` have been done before this is called, else monkey patching will
  not work.
* ``patch_module``: patches a single module, regardless of its settings in the
  ``autopatch_modules`` list.
* ``patch``: patches some modules, you should pass a hash like the one returned
  by ``autopatch_modules``
* ``get_patched_modules``: returns the list of patched modules, a module has been
  correctly patched only if it is in this hash, with a value set to ``true``.

Example:

    require 'ddtrace'

    puts Datadog::Monkey.autopatch_modules                   # lists all modules available for monkey patching
    Datadog::Monkey.patch_module(:redis)                     # patch only one module
    Datadog::Monkey.patch(elasticsearch: false, redis: true) # patch redis, but not elasticsearch
    Datadog::Monkey.patch_all                                # patch all the available modules
    puts Datadog::Monkey.get_patched_modules                 # tells wether modules are patched or not

It is safe to call ``patch_all``, ``patch_module`` or ``patch`` several times.
Make sure the library you want to patch is imported before you call ``patch_module``.
In doubt, check with ``get_patched_modules``.
Once a module is patched, it is not possible to unpatch it.

### Patch Info (PIN)

The Patch Info, AKA ``Pin`` object, gives you control on the integration.

It has one class method:

* ``get_from``: returns the Pin object which has been pinned onto some random
  object. It is safe to call ``get_from`` on any object, but it might return ``nil``.

Some instance methods:

* ``enabled?``: wether tracing is enabled for this object
* ``onto``: applies the patch information to some random object. It is the companion
  function of ``get_from``.

Accessors:

* ``service``: service, you should typically set some meaningful value for this.
* ``app``: application name
* ``tags``: optional tags
* ``app_type``: application type
* ``name``: span name
* ``tracer``: the tracer object used for tracing

By default, a traced integration such as Redis or Elasticsearch carries a Pin object. Eg:

    require 'redis'
    require 'ddtrace'

    Datadog::Monkey.patch_all

    redis = Redis.new
    pin = Datadog::Pin.get_from(redis)
    pin.service = 'my-redis-cache'
    puts redis.get 'my-key' # this will be traced as belonging to 'my-redis-cache' service
    pin.tracer = nil
    puts pin.enabled?       # false
    puts redis.get 'my-key' # this won't be traced, tracing has been disabled now

You can use this object to instrument your own code:

    require 'ddtrace'
    require 'ddtrace/ext/app_types'

    class MyWebSite
      def initialize
        pin = Datadog::Pin.new('my-web-site', app_type: Datadog::Ext::AppTypes::WEB)
        Datadog::Pin.onto(self)
      end

      def serve(something)
        pin = Datadog::Pin.get_from(self)
        pin.tracer.trace('serve') do |span|
          span.resource = something
          span.service = pin.service
          # serve something here
        end
      end
    end

### Debug Mode

If you need to check locally what traces and spans are sent after each traced block, you can enable
a global debug mode for all tracers so that every time a trace is ready to be sent, the content will be
printed in the +STDOUT+. To enable the debug logging, add this code anywhere before using the tracer
for the first time:

    require 'ddtrace'
    require 'sinatra'
    require 'active_record'

    # enable debug mode
    Datadog::Tracer.debug_logging = true

    # use the tracer as usual
    tracer = Datadog.tracer

    get '/' do
      tracer.trace('web.request') do |span|
        # ...
      end
    end

Remember that the debug mode may affect your application performance and so it must not be used
in a production environment.

### Environment and tags

By default, the trace agent (not this library, but the program running in
the background collecting data from various clients) uses the tags
set in the agent config file, see our
[environments tutorial](https://app.datadoghq.com/apm/docs/tutorials/environments) for details.

These values can be overridden at the tracer level:

    Datadog.tracer.set_tags('env' => 'prod')

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
    Datadog.tracer.configure(sampler: sampler)

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

    # Do *not* monkey patch here, we do it "manually", to demo the feature
    # Datadog::Monkey.patch_module(:http)

    uri = URI('http://localhost:4567/')

    Datadog.tracer.trace('web.call') do |span|
      req = Net::HTTP::Get.new(uri)
      req['x-ddtrace-parent_trace_id'] = span.trace_id.to_s
      req['x-ddtrace-parent_span_id'] = span.span_id.to_s

      response = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(req)
      end

      puts response.body
    end

On the server:

    require 'sinatra'
    require 'ddtrace'

    # Do *not* use Sinatra integration, we do it "manually", to demo the feature
    # require 'ddtrace/contrib/sinatra/tracer'

    get '/' do
      parent_trace_id = request.env['HTTP_X_DDTRACE_PARENT_TRACE_ID']
      parent_span_id = request.env['HTTP_X_DDTRACE_PARENT_SPAN_ID']

      Datadog.tracer.trace('web.work') do |span|
         if parent_trace_id && parent_span_id
           span.trace_id = parent_trace_id.to_i
           span.parent_id = parent_span_id.to_i
         end

        'Hello world!'
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

### Glossary

* ``Service``: The name of a set of processes that do the same job. Some examples are ``datadog-web-app`` or ``datadog-metrics-db``.
* ``Resource``: A particular query to a service. For a web application, some examples might be a URL stem like ``/user/home`` or a
handler function like ``web.user.home``. For a SQL database, a resource would be the SQL of the query itself like ``select * from users where id = ?``.
You can track thousands (not millions or billions) of unique resources per services, so prefer resources like ``/user/home`` rather than ``/user/home?id=123456789``.
* ``Span``: A span tracks a unit of work in a service, like querying a database or rendering a template. Spans are associated
with a service and optionally a resource. Spans have names, start times, durations and optional tags.
