require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/active_record/patcher'
require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/rack/middlewares'

require 'ddtrace/contrib/rails/ext'
require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/action_controller'
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
          config = config_with_defaults

          activate_rack!(config)
          activate_active_record!(config)
          set_service_info!(config)

          # By default, default service would be guessed from the script
          # being executed, but here we know better, get it from Rails config.
          config[:tracer].default_service = config[:service_name]
        end

        def self.config_with_defaults
          # We set defaults here instead of in the patcher because we need to wait
          # for the Rails application to be fully initialized.
          Datadog.configuration[:rails].tap do |config|
            config[:service_name] ||= Utils.app_name
            config[:database_service] ||= "#{config[:service_name]}-#{Contrib::ActiveRecord::Utils.adapter_name}"
            config[:controller_service] ||= config[:service_name]
            config[:cache_service] ||= "#{config[:service_name]}-cache"
          end
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
          return unless defined?(::ActiveRecord)

          Datadog.configuration.use(
            :active_record,
            service_name: config[:database_service],
            tracer: config[:tracer]
          )
        end

        def self.set_service_info!(config)
          tracer = config[:tracer]
          tracer.set_service_info(config[:controller_service], Ext::APP, Datadog::Ext::AppTypes::WEB)
          tracer.set_service_info(config[:cache_service], Ext::APP, Datadog::Ext::AppTypes::CACHE)
        end
      end
    end
  end
end
