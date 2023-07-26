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
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end

            option :analytics_enabled do |o|
              o.type :bool
              o.env Ext::ENV_ANALYTICS_ENABLED
              o.default false
            end

            option :analytics_sample_rate do |o|
              o.type :float
              o.env Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
            end

            option :service_name do |o|
              o.default do
                Contrib::SpanAttributeSchema.fetch_service_name(
                  Ext::ENV_SERVICE_NAME,
                  Ext::DEFAULT_PEER_SERVICE_NAME
                )
              end
            end

            option :comment_propagation do |o|
              o.type :string
              o.env Contrib::Propagation::SqlComment::Ext::ENV_DBM_PROPAGATION_MODE
              o.default Contrib::Propagation::SqlComment::Ext::DISABLED
            end

            option :peer_service do |o|
              o.type :string, nilable: true
              o.env Ext::ENV_PEER_SERVICE
            end
          end
        end
      end
    end
  end
end
