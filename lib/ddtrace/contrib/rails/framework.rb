require 'ddtrace/tracer'

require 'ddtrace/contrib/rails/core_extensions'
require 'ddtrace/contrib/rails/action_controller'
require 'ddtrace/contrib/rails/action_view'
require 'ddtrace/contrib/rails/active_record'
require 'ddtrace/contrib/rails/active_support'

module Datadog
  module Contrib
    # TODO[manu]: write docs
    module Rails
      # TODO[manu]: write docs
      module Framework
        def self.init_plugin(config)
          # tracer defaults
          default_config = {
            enabled: true,
            default_service: 'rails-app',
            template_base_path: 'views/',
            tracer: Datadog::Tracer.new()
          }

          # merge and update Rails configurations
          user_config = config[:config].datadog_trace rescue {}
          datadog_config = default_config.merge(user_config)
          ::Rails.configuration.datadog_trace = datadog_config

          # TODO[manu]: set default service details

          # auto-instrument the code
          logger = Logger.new(STDOUT)
          logger.info 'Detected Rails >= 3.x. Enabling auto-instrumentation for core components.'
          Datadog::Contrib::Rails::ActionController.instrument()
          Datadog::Contrib::Rails::ActionView.instrument()
          Datadog::Contrib::Rails::ActiveRecord.instrument()
          Datadog::Contrib::Rails::ActiveSupport.instrument()
        end
      end
    end
  end
end
