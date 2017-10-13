require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/rack/middlewares'

require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/action_controller'
require 'ddtrace/contrib/rails/action_view'
require 'ddtrace/contrib/rails/active_record'
require 'ddtrace/contrib/rails/active_support'
require 'ddtrace/contrib/rails/utils'

# Rails < 3.1
if defined?(::ActiveRecord) && !defined?(::ActiveRecord::Base.connection_config)
  ActiveRecord::Base.class_eval do
    class << self
      def connection_config
        connection_pool.spec.config
      end
    end
  end
end

module Datadog
  module Contrib
    # Instrument Rails.
    module Rails
      # Rails framework code, used to essentially:
      # - handle configuration entries which are specific to Datadog tracing
      # - instrument parts of the framework when needed
      module Framework
        include Base
        register_as :rails

        option :enabled, default: true
        option :auto_instrument, default: false
        option :auto_instrument_redis, default: false
        option :auto_instrument_grape, default: false
        option :default_service, default: 'rails-app'
        option :default_controller_service, default: 'rails-controller'
        option :default_cache_service, default: 'rails-cache'
        option :default_grape_service, default: 'grape'
        option :default_database_service
        option :distributed_tracing_enabled, default: false
        option :template_base_path, default: 'views/'
        option :tracer, default: Datadog.tracer
        option :debug, default: false
        option :trace_agent_hostname, default: Datadog::Writer::HOSTNAME
        option :trace_agent_port, default: Datadog::Writer::PORT
        option :env, default: nil
        option :tags, default: {}

        # configure Datadog settings
        # rubocop:disable Metrics/MethodLength
        def self.configure(rails_config)
          user_config = rails_config[:config].datadog_trace rescue {}
          Datadog.configuration.use(:rails, user_config)
          tracer = Datadog.configuration[:rails][:tracer]

          tracer.enabled = get_option(:enabled)
          tracer.class.debug_logging = get_option(:debug)

          tracer.configure(
            hostname: get_option(:trace_agent_hostname),
            port: get_option(:trace_agent_port)
          )

          tracer.set_tags(get_option(:tags))
          tracer.set_tags('env' => get_option(:env)) if get_option(:env)

          tracer.set_service_info(
            get_option(:default_service),
            'rack',
            Datadog::Ext::AppTypes::WEB
          )

          tracer.set_service_info(
            get_option(:default_controller_service),
            'rails',
            Datadog::Ext::AppTypes::WEB
          )
          tracer.set_service_info(
            get_option(:default_cache_service),
            'rails',
            Datadog::Ext::AppTypes::CACHE
          )

          # By default, default service would be guessed from the script
          # being executed, but here we know better, get it from Rails config.
          tracer.default_service = get_option(:default_service)

          Datadog.configuration[:rack][:tracer] = tracer
          Datadog.configuration[:rack][:default_service] = get_option(:default_service)
          Datadog.configuration[:rack][:distributed_tracing_enabled] = get_option(:distributed_tracing_enabled)

          if defined?(::ActiveRecord)
            begin
              # set default database service details and store it in the configuration
              conn_cfg = ::ActiveRecord::Base.connection_config()
              adapter_name = Datadog::Contrib::Rails::Utils.normalize_vendor(conn_cfg[:adapter])
              set_option(:default_database_service, adapter_name) unless get_option(:default_database_service)
              tracer.set_service_info(
                get_option(:default_database_service),
                adapter_name,
                Datadog::Ext::AppTypes::DB
              )
            rescue StandardError => e
              Datadog::Tracer.log.warn("Unable to get database config (#{e}), skipping ActiveRecord instrumentation")
            end
          end

          # update global configurations
          ::Rails.configuration.datadog_trace = to_h
        end

        def self.auto_instrument_redis
          return unless get_option(:auto_instrument_redis)
          Datadog::Tracer.log.debug('Enabling auto-instrumentation for Redis client')

          # patch the Redis library and reload the CacheStore if it was using Redis
          Datadog::Monkey.patch_module(:redis)

          # reload the cache store if it's available and it's using Redis
          return unless defined?(::ActiveSupport::Cache::RedisStore) &&
                        defined?(::Rails.cache) &&
                        ::Rails.cache.is_a?(::ActiveSupport::Cache::RedisStore)
          Datadog::Tracer.log.debug('Enabling auto-instrumentation for redis-rails connector')

          # backward compatibility: Rails 3.x doesn't have `cache=` method
          cache_store = ::Rails.configuration.cache_store
          cache_instance = ::ActiveSupport::Cache.lookup_store(cache_store)
          if ::Rails::VERSION::MAJOR.to_i == 3
            silence_warnings { Object.const_set 'RAILS_CACHE', cache_instance }
          elsif ::Rails::VERSION::MAJOR.to_i > 3
            ::Rails.cache = cache_instance
          end
        end

        def self.auto_instrument_grape
          return unless get_option(:auto_instrument_grape)

          # patch the Grape library so that endpoints are traced
          Datadog::Monkey.patch_module(:grape)

          # update the Grape pin object
          pin = Datadog::Pin.get_from(::Grape)
          return unless pin && pin.enabled?
          pin.tracer = get_option(:tracer)
          pin.service = get_option(:default_grape_service)
        end

        # automatically instrument all Rails component
        def self.auto_instrument
          return unless get_option(:auto_instrument)
          Datadog::Tracer.log.debug('Enabling auto-instrumentation for core components')

          # instrumenting Rails framework
          Datadog::Contrib::Rails::ActionController.instrument()
          Datadog::Contrib::Rails::ActionView.instrument()
          Datadog::Contrib::Rails::ActiveRecord.instrument()
          Datadog::Contrib::Rails::ActiveSupport.instrument()
        end
      end
    end
  end
end
