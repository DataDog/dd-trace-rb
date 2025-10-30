# frozen_string_literal: true

require_relative 'configuration'
require_relative '../core/configuration'

module Datadog
  module DataStreams
    # Extends Datadog with Data Streams Monitoring features
    module Extensions
      # Inject Data Streams settings into global configuration.
      def self.activate!
        Core::Configuration::Settings.extend(Configuration::Settings)
      end
    end
  end
end
