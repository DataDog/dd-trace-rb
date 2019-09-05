require 'ddtrace/pin'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/active_record/integration'
require 'ddtrace/contrib/active_support/integration'
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
        # configure Datadog settings
        def self.setup
          config = config_with_defaults

          activate_rack!(config)
          activate_active_support!(config)
          activate_action_pack!(config)
          activate_action_view!(config)
          activate_active_record!(config)

          # By default, default service would be guessed from the script
          # being executed, but here we know better, get it from Rails config.
          config[:tracer].default_service = config[:service_name]
        end

        def self.config_with_defaults
          # We set defaults here instead of in the patcher because we need to wait
          # for the Rails application to be fully initialized.
          Datadog.configuration[:rails].tap do |config|
            config.service_name ||= Utils.app_name
            config.database_service ||= "#{config.service_name}-#{Contrib::ActiveRecord::Utils.adapter_name}"
            config.controller_service ||= config.service_name
            config.cache_service ||= "#{config.service_name}-cache"
          end
        end

        def self.activate_rack!(config)
          config.activate!(:rack) do |rack|
            rack.tracer = config.tracer
            rack.application = ::Rails.application
            rack.service_name = config.service_name
            rack.middleware_names = config.middleware_names
            rack.distributed_tracing = config.distributed_tracing
          end
        end

        def self.activate_active_support!(config)
          return unless defined?(::ActiveSupport)

          config.activate!(:active_support) do |active_support|
            active_support.cache_service = config.cache_service
            active_support.tracer = config.tracer
          end
        end

        def self.activate_action_pack!(config)
          return unless defined?(::ActionPack)

          config.activate!(:action_pack) do |action_pack|
            action_pack.service_name = config.service_name
            action_pack.tracer = config.tracer
          end
        end

        def self.activate_action_view!(config)
          return unless defined?(::ActionView)

          config.activate!(:action_view) do |action_view|
            action_view.service_name = config.service_name
            action_view.tracer = config.tracer
          end
        end

        def self.activate_active_record!(config)
          return unless defined?(::ActiveRecord)

          config.activate!(:active_record) do |active_record|
            active_record.service_name = config.database_service
            active_record.tracer = config.tracer
          end
        end
      end
    end
  end
end
