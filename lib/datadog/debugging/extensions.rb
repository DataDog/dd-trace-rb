# frozen_string_literal: true

require_relative 'configuration'

module Datadog
  module Debugging
    # Extends Datadog tracing with Debugging features
    module Extensions
      # Inject Debugging into global objects.
      def self.activate!
        Core::Configuration::Settings.extend(Configuration::Settings)
      end
    end
  end
end
