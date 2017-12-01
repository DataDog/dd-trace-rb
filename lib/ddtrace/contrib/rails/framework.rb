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
        # configure Datadog settings
        def self.configure(rails_config)
          user_config = rails_config[:config].datadog_trace rescue {}
          Datadog.configuration.use(:rails, user_config)
          config = Datadog.configuration[:rails]
          tracer = config[:tracer]
          config[:service_name] ||= Utils.app_name

          Datadog.configuration.use(
            :rack,
            tracer: tracer,
            service_name: config[:service_name],
            distributed_tracing_enabled: config[:distributed_tracing_enabled]
          )

          config[:controller_service] ||= config[:service_name]
          config[:cache_service] ||= "#{config[:service_name]}-cache"

          tracer.set_service_info(config[:controller_service], 'rails', Ext::AppTypes::WEB)
          tracer.set_service_info(config[:cache_service], 'rails', Ext::AppTypes::CACHE)

          # By default, default service would be guessed from the script
          # being executed, but here we know better, get it from Rails config.
          tracer.default_service = config[:service_name]

          if defined?(::ActiveRecord)
            begin
              # set default database service details and store it in the configuration
              conn_cfg = ::ActiveRecord::Base.connection_config()
              adapter_name = Datadog::Contrib::Rails::Utils.normalize_vendor(conn_cfg[:adapter])
              config[:database_service] ||= "#{config[:service_name]}-#{adapter_name}"
              tracer.set_service_info(config[:database_service], adapter_name, Ext::AppTypes::DB)
            rescue StandardError => e
              Datadog::Tracer.log.warn("Unable to get database config (#{e}), skipping ActiveRecord instrumentation")
            end
          end

          # update global configurations
          ::Rails.configuration.datadog_trace = Datadog.registry[:rails].to_h
        end
      end
    end
  end
end
