require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/action_controller'
require 'ddtrace/contrib/rails/action_view'
require 'ddtrace/contrib/rails/active_record'
require 'ddtrace/contrib/rails/active_support'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    # TODO[manu]: write docs
    module Rails
      # TODO[manu]: write docs
      module Framework
        # default configurations for the Rails integration; by default
        # the Datadog.tracer is enabled, while the Rails auto instrumentation
        # is kept disabled.
        DEFAULT_CONFIG = {
          enabled: true,
          auto_instrument: false,
          auto_instrument_redis: false,
          default_service: 'rails-app',
          default_cache_service: 'rails-cache',
          template_base_path: 'views/',
          tracer: Datadog.tracer,
          debug: false,
          trace_agent_hostname: Datadog::Writer::HOSTNAME,
          trace_agent_port: Datadog::Writer::PORT,
          env: Rails.env
        }.freeze

        # configure Datadog settings
        def self.configure(config)
          # tracer defaults
          # merge default configurations with users settings
          user_config = config[:config].datadog_trace rescue {}
          datadog_config = DEFAULT_CONFIG.merge(user_config)
          datadog_config[:tracer].enabled = datadog_config[:enabled]

          # set debug logging
          Datadog::Tracer.debug_logging = datadog_config[:debug]

          # set the address of the trace agent
          datadog_config[:tracer].configure(
            hostname: datadog_config[:trace_agent_hostname],
            port: datadog_config[:trace_agent_port]
          )

          # set default service details
          datadog_config[:tracer].set_service_info(
            datadog_config[:default_service],
            'rails',
            Datadog::Ext::AppTypes::WEB
          )

          datadog_config[:tracer].set_service_info(
            datadog_config[:default_cache_service],
            'rails',
            Datadog::Ext::AppTypes::CACHE
          )

          datadog_config[:tracer].set_tag('env', datadog_config[:env])

          if defined?(::ActiveRecord)
            begin
              # set default database service details and store it in the configuration
              conn_cfg = ::ActiveRecord::Base.connection_config()
              adapter_name = Datadog::Contrib::Rails::Utils.normalize_vendor(conn_cfg[:adapter])
              database_service = datadog_config.fetch(:default_database_service, adapter_name)
              datadog_config[:default_database_service] = database_service
              datadog_config[:tracer].set_service_info(
                database_service,
                adapter_name,
                Datadog::Ext::AppTypes::DB
              )
            rescue StandardError => e
              Datadog::Tracer.log.warn("Unable to get database config (#{e}), skipping ActiveRecord instrumentation")
            end
          end

          # update global configurations
          ::Rails.configuration.datadog_trace = datadog_config
        end

        def self.auto_instrument_redis
          return unless ::Rails.configuration.datadog_trace[:auto_instrument_redis]
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

        # automatically instrument all Rails component
        def self.auto_instrument
          return unless ::Rails.configuration.datadog_trace[:auto_instrument]
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
