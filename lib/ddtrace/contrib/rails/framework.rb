require 'ddtrace'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/action_controller'
require 'ddtrace/contrib/rails/action_view'
require 'ddtrace/contrib/rails/active_record' if defined?(::ActiveRecord)
require 'ddtrace/contrib/rails/active_support'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    # TODO[manu]: write docs
    module Rails
      # TODO[manu]: write docs
      module Framework
        # get Rails operation mode; Rails ships with 'production' as a default
        # environment to set the entire application in production mode. This should
        # be a reasonable default to disable the tracer in other environments.
        PRODUCTION_MODE = ::Rails.env.production?

        # the default configuration
        DEFAULT_CONFIG = {
          enabled: PRODUCTION_MODE,
          auto_instrument: PRODUCTION_MODE,
          auto_instrument_redis: PRODUCTION_MODE,
          default_service: 'rails-app',
          default_cache_service: 'rails-cache',
          template_base_path: 'views/',
          tracer: Datadog.tracer,
          debug: false,
          trace_agent_hostname: Datadog::Writer::HOSTNAME,
          trace_agent_port: Datadog::Writer::PORT
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

          # set default database service details and store it in the configuration
          if defined?(::ActiveRecord)
            begin
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
              Datadog::Tracer.log.info("cannot configuring database service (#{e}), skipping activerecord instrumentation")
            end
          end

          # update global configurations
          ::Rails.configuration.datadog_trace = datadog_config
        end

        def self.auto_instrument_redis
          Datadog::Tracer.log.debug('instrumenting redis')
          return unless (defined? ::Rails.cache) && ::Rails.cache.respond_to?(:data)
          Datadog::Tracer.log.debug('redis cache exists')
          pin = Datadog::Pin.get_from(::Rails.cache.data)
          return unless pin
          Datadog::Tracer.log.debug('redis cache pin is set')
          pin.tracer = nil unless ::Rails.configuration.datadog_trace[:auto_instrument_redis]
        end

        # automatically instrument all Rails component
        def self.auto_instrument
          return unless ::Rails.configuration.datadog_trace[:auto_instrument]
          Datadog::Tracer.log.info('Detected Rails >= 3.x. Enabling auto-instrumentation for core components.')
          Datadog::Contrib::Rails::ActionController.instrument()
          Datadog::Contrib::Rails::ActionView.instrument()
          Datadog::Contrib::Rails::ActiveRecord.instrument() if defined?(::ActiveRecord)
          Datadog::Contrib::Rails::ActiveSupport.instrument()

          # by default, Rails 3 doesn't instrument the cache system
          return unless ::Rails::VERSION::MAJOR.to_i == 3
          ::ActiveSupport::Cache::Store.instrument = true
        end
      end
    end
  end
end
