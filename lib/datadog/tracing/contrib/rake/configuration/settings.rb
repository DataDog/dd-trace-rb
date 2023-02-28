require 'set'

require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Rake
        module Configuration
          # Custom settings for the Rake integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end

            option :analytics_enabled do |o|
              o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
              o.lazy
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
              o.lazy
            end

            option :quantize, default: {}
            option :service_name

            # A list of rake tasks, using their string names, to be instrumented.
            # An empty list, or not setting this option means no task is instrumented.
            # Automatically instrumenting all Rake tasks can lead to long-running tasks
            # causing undue memory accumulation, as the trace for such tasks is never flushed.
            option :tasks do |o|
              o.default { [] }
              o.lazy
              o.on_set do |value|
                # DEV: It should be possible to modify the value after it's set. E.g. for normalization.
                options[:tasks].instance_variable_set(:@value, value.map(&:to_s).to_set)
              end
            end
          end
        end
      end
    end
  end
end
