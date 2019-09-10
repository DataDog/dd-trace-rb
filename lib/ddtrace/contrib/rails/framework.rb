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

          config.apply_and_activate!(:rack)
          config.apply_and_activate!(:active_support) if defined?(::ActiveSupport)
          config.apply_and_activate!(:action_pack) if defined?(::ActionPack)
          config.apply_and_activate!(:action_view) if defined?(::ActionView)
          config.apply_and_activate!(:active_record) if defined?(::ActiveRecord)

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
      end
    end
  end
end
