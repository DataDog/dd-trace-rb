require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/active_record/patcher'
require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/rack/middlewares'

require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/action_controller'
require 'ddtrace/contrib/rails/action_view'
require 'ddtrace/contrib/rails/active_support'
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

          activate_rack!(config)
          activate_active_record!(config)

          config[:controller_service] ||= config[:service_name]
          config[:cache_service] ||= "#{config[:service_name]}-cache"

          tracer.set_service_info(config[:controller_service], 'rails', Ext::AppTypes::WEB)
          tracer.set_service_info(config[:cache_service], 'rails', Ext::AppTypes::CACHE)

          # By default, default service would be guessed from the script
          # being executed, but here we know better, get it from Rails config.
          tracer.default_service = config[:service_name]
        end

        def self.activate_rack!(config)
          Datadog.configuration.use(
            :rack,
            tracer: config[:tracer],
            application: ::Rails.application,
            service_name: config[:service_name],
            middleware_names: config[:middleware_names],
            distributed_tracing: config[:distributed_tracing]
          )
        end

        def self.activate_active_record!(config)
          Datadog.configuration.use(
            :active_record,
            service_name: config[:database_service],
            tracer: config[:tracer]
          )
        end
      end
    end
  end
end
