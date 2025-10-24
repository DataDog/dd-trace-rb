# frozen_string_literal: true

require_relative '../core/configuration'
require_relative 'configuration'

module Datadog
  module OpenFeature
    module Extensions
      def self.activate!
        Core::Configuration::Settings.extend(Configuration::Settings)
      end
    end
  end
end
