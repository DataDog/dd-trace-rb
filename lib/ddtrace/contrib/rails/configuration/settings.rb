require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Rails
      module Configuration
        # Custom settings for the Rails integration
        class Settings < Contrib::Configuration::Settings
          DEFAULT_HEADERS = {
            response: %w[Content-Type X-Request-ID]
          }.freeze

          option :cache_service
          option :controller_service
          option :database_service, depends_on: [:service_name] do |value|
            value.tap do
              # Update ActiveRecord service name too
              Datadog.configuration[:active_record][:service_name] = value
            end
          end
          option :distributed_tracing, default: false
          option :exception_controller, default: nil
          option :headers, default: DEFAULT_HEADERS
          option :middleware, default: true
          option :middleware_names, default: false
          option :template_base_path, default: 'views/'
        end
      end
    end
  end
end
