require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/active_record/integration'
require 'ddtrace/contrib/active_support/integration'
require 'ddtrace/contrib/action_cable/integration'
require 'ddtrace/contrib/action_pack/integration'
require 'ddtrace/contrib/action_view/integration'
require 'ddtrace/contrib/grape/endpoint'

require 'ddtrace/contrib/rails/ext'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    # Instrument Rails.
    module Rails
      # Rails framework code, used to essentially:
      # - handle configuration entries which are specific to Datadog tracing
      # - instrument parts of the framework when needed
      module Framework
        # After the Rails application finishes initializing, we configure the Rails
        # integration and all its sub-components with the application information
        # available.
        # We do this after the initialization because not all the information we
        # require is available before then.
        def self.setup
          # NOTE: #configure has the side effect of rebuilding trace components.
          #       During a typical Rails application lifecycle, we will see trace
          #       components initialized twice because of this. This is necessary
          #       because key configuration is not available until after the Rails
          #       application has fully loaded, and some of this configuration is
          #       used to reconfigure tracer components with Rails-sourced defaults.
          #       This is a trade-off we take to get nice defaults.
          Datadog.configure do |datadog_config|
            rails_config = config_with_defaults(datadog_config)

            # By default, default service would be guessed from the script
            # being executed, but here we know better, get it from Rails config.
            # Don't set this if service has been explicitly provided by the user.
            datadog_config.service ||= rails_config[:service_name]

            activate_rack!(datadog_config, rails_config)
            activate_action_cable!(datadog_config, rails_config)
            activate_active_support!(datadog_config, rails_config)
            activate_action_pack!(datadog_config, rails_config)
            activate_action_view!(datadog_config, rails_config)
            activate_active_record!(datadog_config, rails_config)
          end
        end

        def self.config_with_defaults(datadog_config)
          # We set defaults here instead of in the patcher because we need to wait
          # for the Rails application to be fully initialized.
          datadog_config[:rails].tap do |config|
            config[:service_name] ||= (Datadog.configuration.service || Utils.app_name)
            config[:database_service] ||= "#{config[:service_name]}-#{Contrib::ActiveRecord::Utils.adapter_name}"
            config[:controller_service] ||= config[:service_name]
            config[:cache_service] ||= "#{config[:service_name]}-cache"
          end
        end

        def self.activate_rack!(datadog_config, rails_config)
          datadog_config.use(
            :rack,
            application: ::Rails.application,
            service_name: rails_config[:service_name],
            middleware_names: rails_config[:middleware_names],
            distributed_tracing: rails_config[:distributed_tracing]
          )
        end

        def self.activate_active_support!(datadog_config, rails_config)
          return unless defined?(::ActiveSupport)

          datadog_config.use(
            :active_support,
            cache_service: rails_config[:cache_service]
          )
        end

        def self.activate_action_cable!(datadog_config, rails_config)
          return unless defined?(::ActionCable)

          datadog_config.use(
            :action_cable,
            service_name: "#{rails_config[:service_name]}-#{Contrib::ActionCable::Ext::SERVICE_NAME}"
          )
        end

        def self.activate_action_pack!(datadog_config, rails_config)
          return unless defined?(::ActionPack)

          # TODO: This is configuring ActionPack but not patching. It will queue ActionPack
          #       for patching, but patching won't take place until Datadog.configure completes.
          #       Should we manually patch here?

          datadog_config.use(
            :action_pack,
            service_name: rails_config[:service_name]
          )
        end

        def self.activate_action_view!(datadog_config, rails_config)
          return unless defined?(::ActionView)

          datadog_config.use(
            :action_view,
            service_name: rails_config[:service_name]
          )
        end

        def self.activate_active_record!(datadog_config, rails_config)
          return unless defined?(::ActiveRecord)

          datadog_config.use(
            :active_record,
            service_name: rails_config[:database_service]
          )
        end
      end
    end
  end
end
