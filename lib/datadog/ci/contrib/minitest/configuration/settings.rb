# frozen_string_literal: true

require_relative '../../../../tracing/contrib/configuration/settings'
require_relative '../ext'

module Datadog
  module CI
    module Contrib
      module Minitest
        module Configuration
          # Custom settings for the Minitest integration
          # TODO: mark as `@public_api` when GA
          class Settings < Datadog::Tracing::Contrib::Configuration::Settings
            option :enabled do |o|
              o.env_var Ext::ENV_ENABLED
              o.default true
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :service_name do |o|
              o.default { Datadog.configuration.service_without_fallback || Ext::SERVICE_NAME }
            end

            option :operation_name do |o|
              o.env_var Ext::ENV_OPERATION_NAME
              o.default Ext::OPERATION_NAME
            end
          end
        end
      end
    end
  end
end
