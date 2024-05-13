# frozen_string_literal: true

require_relative 'configuration'

module Datadog
  module Debugger
    # Extends Datadog tracing with Debugger features
    module Extensions
      # Inject Debugger into global objects.
      def self.activate!
        Core::Configuration::Settings.extend(Configuration::Settings)
      end
    end
  end
end
