# frozen_string_literal: true

require_relative '../../configuration/settings'

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        module Configuration
          # Custom settings for the WaterDrop integration
          class Settings < Contrib::Configuration::Settings
            option :enabled, default: true
            option :service_name, default: nil
            option :distributed_tracing, default: true
            option :analytics_enabled, default: false
            option :analytics_sample_rate, default: 1.0
          end
        end
      end
    end
  end
end
