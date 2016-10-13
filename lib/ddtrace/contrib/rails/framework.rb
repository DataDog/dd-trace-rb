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
        # configure Datadog settings
        def self.configure(config)
          # tracer defaults
          default_config = {
            enabled: true,
            auto_instrument: true,
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
        end

        # automatically instrument all Rails component
        def self.auto_instrument
          if ::Rails.configuration.datadog_trace[:auto_instrument]
            Datadog::Tracer.log.info('Detected Rails >= 3.x. Enabling auto-instrumentation for core components.')
            Datadog::Contrib::Rails::ActionController.instrument()
            Datadog::Contrib::Rails::ActionView.instrument()
            Datadog::Contrib::Rails::ActiveRecord.instrument()
            Datadog::Contrib::Rails::ActiveSupport.instrument()

            # by default, Rails 3 doesn't instrument the cache system
            if ::Rails::VERSION::MAJOR.to_i == 3
              ::ActiveSupport::Cache::Store.instrument = true
            end
          end
        end
      end
    end
  end
end
