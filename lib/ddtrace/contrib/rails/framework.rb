require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/rack/middlewares'

require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/active_support'
require 'ddtrace/contrib/rails/active_support/callbacks'
require 'ddtrace/contrib/rails/action_controller'
require 'ddtrace/contrib/rails/action_controller/callbacks'
require 'ddtrace/contrib/rails/action_view'
require 'ddtrace/contrib/rails/active_record'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    # Instrument Rails.
    module Rails
      # Rails framework code, used to essentially:
      # - handle configuration entries which are specific to Datadog tracing
      # - instrument parts of the framework when needed
      module Framework
        # configure Datadog settings
        def self.setup
          config = Datadog.configuration[:rails]
          config[:service_name] ||= Utils.app_name
          tracer = config[:tracer]

          Datadog.configuration.use(
            :rack,
            tracer: tracer,
            service_name: config[:service_name],
            distributed_tracing: config[:distributed_tracing]
          )

          config[:controller_service] ||= config[:service_name]
          config[:cache_service] ||= "#{config[:service_name]}-cache"

          tracer.set_service_info(config[:controller_service], 'rails', Ext::AppTypes::WEB)
          tracer.set_service_info(config[:cache_service], 'rails', Ext::AppTypes::CACHE)
          set_database_service

          # By default, default service would be guessed from the script
          # being executed, but here we know better, get it from Rails config.
          tracer.default_service = config[:service_name]
        end

        def self.set_database_service
          return unless defined?(::ActiveRecord)

          config = Datadog.configuration[:rails]
          adapter_name = Utils.adapter_name
          config[:database_service] ||= "#{config[:service_name]}-#{adapter_name}"
          config[:tracer].set_service_info(config[:database_service], adapter_name, Ext::AppTypes::DB)
        rescue => e
          Tracer.log.warn("Unable to get database config (#{e}), skipping ActiveRecord instrumentation")
        end
      end
    end
  end
end
