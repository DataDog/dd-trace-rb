require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/graphql/ext'

module Datadog
  module Contrib
    module GraphQL
      module Configuration
        # Custom settings for the GraphQL integration
        class Settings < Contrib::Configuration::Settings
          option :schemas
          option :service_name, default: Ext::SERVICE_NAME, depends_on: [:tracer] do |value|
            get_option(:tracer).set_service_info(value, Ext::APP, Datadog::Ext::AppTypes::WEB)
            value
          end
        end
      end
    end
  end
end
