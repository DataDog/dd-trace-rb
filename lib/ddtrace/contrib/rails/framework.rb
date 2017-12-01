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
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        def self.configure(rails_config)
          user_config = rails_config[:config].datadog_trace rescue {}
          Datadog.configuration.use(:rails, user_config)
          tracer = Datadog.configuration[:rails][:tracer]

          tracer.enabled = Datadog.configuration[:rails][:enabled]
          tracer.class.debug_logging = Datadog.configuration[:rails][:debug]

          tracer.configure(
            hostname: Datadog.configuration[:rails][:trace_agent_hostname],
            port: Datadog.configuration[:rails][:trace_agent_port],
            priority_sampling: Datadog.configuration[:rails][:priority_sampling]
          )

          tracer.set_tags(Datadog.configuration[:rails][:tags])
          tracer.set_tags('env' => Datadog.configuration[:rails][:env]) if Datadog.configuration[:rails][:env]

          tracer.set_service_info(
            Datadog.configuration[:rails][:service_name],
            'rack',
            Datadog::Ext::AppTypes::WEB
          )

          tracer.set_service_info(
            Datadog.configuration[:rails][:controller_service],
            'rails',
            Datadog::Ext::AppTypes::WEB
          )
          tracer.set_service_info(
            Datadog.configuration[:rails][:cache_service],
            'rails',
            Datadog::Ext::AppTypes::CACHE
          )

          # By default, default service would be guessed from the script
          # being executed, but here we know better, get it from Rails config.
          tracer.default_service = Datadog.configuration[:rails][:service_name]

          Datadog.configuration[:rack][:tracer] = tracer
          Datadog.configuration[:rack][:service_name] = Datadog.configuration[:rails][:service_name]
          Datadog.configuration[:rack][:distributed_tracing_enabled] = \
            Datadog.configuration[:rails][:distributed_tracing_enabled]

          if defined?(::ActiveRecord)
            begin
              # set default database service details and store it in the configuration
              conn_cfg = ::ActiveRecord::Base.connection_config()
              adapter_name = Datadog::Contrib::Rails::Utils.normalize_vendor(conn_cfg[:adapter])
              Datadog.configuration[:rails][:database_service] ||= adapter_name
              tracer.set_service_info(
                Datadog.configuration[:rails][:database_service],
                adapter_name,
                Datadog::Ext::AppTypes::DB
              )
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
