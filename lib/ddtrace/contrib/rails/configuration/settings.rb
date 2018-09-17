require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Rails
      module Configuration
        # Custom options for Rails configuration
        class Settings < Contrib::Configuration::Settings
          option :controller_service
          option :cache_service
          option :database_service, depends_on: [:service_name] do |value|
            value.tap do
              # Update ActiveRecord service name too
              Datadog.configuration[:active_record][:service_name] = value
            end
          end
          option :middleware_names, default: false
          option :distributed_tracing, default: false
          option :template_base_path, default: 'views/'
          option :exception_controller, default: nil
        end
      end
    end
  end
end
