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
              o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
              o.lazy
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
              o.lazy
            end

            option :tag_job_data do |o|
              o.default { env_to_bool(Ext::ENV_TAG_JOB_DATA, false) }
              o.lazy
            end

            option :tag_job_tags do |o|
              o.default { env_to_bool(Ext::ENV_TAG_JOB_TAGS, false) }
              o.lazy
            end

            option :service_name
          end
        end
      end
    end
  end
end
