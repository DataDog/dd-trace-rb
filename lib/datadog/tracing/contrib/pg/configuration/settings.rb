# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'

require_relative '../../propagation/sql_comment/ext'

module Datadog
  module Tracing
    module Contrib
      module Pg
        module Configuration
          # Custom settings for the Pg integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.env_var Ext::ENV_ENABLED
              o.default true
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :analytics_enabled do |o|
              o.env_var Ext::ENV_ANALYTICS_ENABLED
              o.default false
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :analytics_sample_rate do |o|
              o.env_var Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
              o.setter do |value|
                val_to_float(value)
              end
            end

            option :service_name do |o|
              o.env_var Ext::ENV_SERVICE_NAME
              o.setter do |value|
                Contrib::SpanAttributeSchema.fetch_service_name(
                  value,
                  Ext::DEFAULT_PEER_SERVICE_NAME
                )
              end
            end

            option :comment_propagation do |o|
              o.env_var Contrib::Propagation::SqlComment::Ext::ENV_DBM_PROPAGATION_MODE
              o.default Contrib::Propagation::SqlComment::Ext::DISABLED
            end
          end
        end
      end
    end
  end
end
