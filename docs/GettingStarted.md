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
provides auto instrumentation for the following web frameworks:

* [Ruby on Rails](#label-Ruby+on+Rails)
* [Sinatra](#label-Sinatra)

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

#### Configure the tracer with initializers

All tracing settings are namespaced under the ``Rails.configuration.datadog_tracer`` hash. To change the default behavior
of the Datadog tracer, you can override the following defaults:

    # config/initializers/datadog-tracer.rb

    Rails.configuration.datadog_trace = {
      enabled: true,
      auto_instrument: false,
      auto_instrument_redis: false,
      default_service: 'rails-app',
      default_database_service: 'postgresql',
      default_cache_service: 'rails-cache',
      template_base_path: 'views/',
      tracer: Datadog.tracer,
      debug: false,
      trace_agent_hostname: 'localhost',
      trace_agent_port: 7777
    }

Available settings are:

* ``enabled``: defines if the ``tracer`` is enabled or not. If set to ``false`` the code could be still instrumented
  because of other settings, but no spans are sent to the local trace agent.
* ``auto_instrument``: if set to +true+ the code will be automatically instrumented. You may change this value
  with a condition, to enable the auto-instrumentation only for particular environments (production, staging, etc...).
* ``auto_instrument_redis``: if set to ``true`` Redis calls will be traced as such. Calls to Redis cache may be
  still instrumented but you will not have the detail of low-level Redis calls.
* ``default_service``: set the service name used when tracing application requests. Defaults to ``rails-app``
* ``default_database_service``: set the database service name used when tracing database activity. Defaults to the
  current adapter name, so if you're using PostgreSQL it will be ``postgres``.
* ``default_cache_service``: set the cache service name used when tracing cache activity. Defaults to ``rails-cache``
* ``template_base_path``: used when the template name is parsed in the auto instrumented code. If you don't store
  your templates in the ``views/`` folder, you may need to change this value
* ``tracer``: is the global tracer used by the tracing application. Usually you don't need to change that value
  unless you're already using a different initialized ``tracer`` somewhere else
* ``debug``: set to true to enable debug logging.
* ``trace_agent_hostname``: set the hostname of the trace agent.
* ``trace_agent_port``: set the port the trace agent is listening on.

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

## Other libraries

### Redis

The Redis integration will trace simple calls as well as pipelines.

    require 'redis'
    require 'ddtrace'

    Datadog::Monkey.patch_module(:redis) # you need to explicitly patch it

    # now do your Redis stuff, eg:
    redis = Redis.new
    redis.set 'foo', 'bar' # traced!

### Elastic Search

The Elasticsearch integration will trace any call to ``perform_request``
in the ``Client`` object:

    require 'elasticsearch/transport'
    require 'ddtrace'

    Datadog::Monkey.patch_module(:elasticsearch) # you need to explicitly patch it

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

    Datadog::Monkey.patch_module(:http) # you need to explicitly patch it

    Net::HTTP.start('127.0.0.1', 8080) do |http|
      request = Net::HTTP::Get.new '/index'
      response = http.request request
    end

    content = Net::HTTP.get(URI('http://127.0.0.1/index.html'))

### Sidekiq

The Sidekiq integration is a server-side middleware which will trace job
executions. It can be added as any other Sidekiq middleware:

    require 'sidekiq'
    require 'ddtrace'
    require 'ddtrace/contrib/sidekiq/tracer'

    Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        chain.add(Datadog::Contrib::Sidekiq::Tracer, debug: true)
      end
    end

#### Configure the tracer

To modify the default configuration, simply pass arguments to the middleware.
For example, to change the default service name and activate the debug mode:

    Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        chain.add(Datadog::Contrib::Sidekiq::Tracer,
                  default_service: 'my_app', debug: true)
      end
    end

Available settings are:

* ``enabled``: define if the ``tracer`` is enabled or not. If set to
  ``false``, the code is still instrumented but no spans are sent to the local
  trace agent.
* ``default_service``: set the service name used when tracing application
  requests. Defaults to ``sidekiq``.
* ``tracer``: set the tracer to use. Usually you don't need to change that
  value unless you're already using a different initialized tracer somewhere
  else.
* ``debug``: set to ``true`` to enable debug logging.
* ``trace_agent_hostname``: set the hostname of the trace agent.
* ``trace_agent_port``: set the port the trace agent is listening on.

## Advanced usage

### Manual Instrumentation

If you aren't using a supported framework instrumentation, you may want to to manually instrument your code.
Adding tracing to your code is very simple. As an example, let’s imagine we have a web server and we want
to trace requests to the home page:

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
    require 'activerecord'

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

### Supported Versions

#### Ruby interpreters

The Datadog Trace Client has been tested with the following Ruby versions:

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
