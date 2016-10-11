require 'ddtrace/tracer'
require 'ddtrace/ext/app_types'

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

          # merge default configurations with users settings
          user_config = config[:config].datadog_trace rescue {}
          datadog_config = default_config.merge(user_config)
          datadog_config[:tracer].enabled = datadog_config[:enabled]

          # set default service details
          datadog_config[:tracer].set_service_info(
            datadog_config[:default_service],
            'rails',
            Datadog::Ext::AppTypes::WEB
          )

          # update global configurations
          ::Rails.configuration.datadog_trace = datadog_config

          if datadog_config[:enabled]
            # auto-instrument the code
            Datadog::Tracer.log.info('Detected Rails >= 3.x. Enabling auto-instrumentation for core components.')
            Datadog::Contrib::Rails::ActionController.instrument()
            Datadog::Contrib::Rails::ActionView.instrument()
            Datadog::Contrib::Rails::ActiveRecord.instrument()
            Datadog::Contrib::Rails::ActiveSupport.instrument()
          end
        end
      end
    end
  end
end
