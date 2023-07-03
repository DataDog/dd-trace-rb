# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Qless
        module Configuration
          # Custom settings for the Qless integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
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

            option :tag_job_data do |o|
              o.env_var Ext::ENV_TAG_JOB_DATA
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :tag_job_tags do |o|
              o.env_var Ext::ENV_TAG_JOB_TAGS
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :service_name
          end
        end
      end
    end
  end
end
