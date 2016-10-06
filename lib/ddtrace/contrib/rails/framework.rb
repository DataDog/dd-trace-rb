require 'ddtrace/tracer'

module Datadog
  module Instrument
    # some stuff
    module RailsFramework
      def self.init_plugin(config)
        # tracer defaults
        default_config = {
          enabled: true,
          default_service: 'rails-app',
          tracer: Datadog::Tracer.new()
        }

        # merge and update Rails configurations
        user_config = config[:config].datadog_trace rescue {}
        datadog_config = default_config.merge(user_config)
        Rails.configuration.datadog_trace = datadog_config

        # TODO[manu]: set default service details

        # auto-instrument the code
      end
    end
  end
end
