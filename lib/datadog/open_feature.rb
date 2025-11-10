# frozen_string_literal: true

require_relative 'core/configuration'
require_relative 'open_feature/configuration'

module Datadog
  # A namespace for the OpenFeature component.
  module OpenFeature
    Core::Configuration::Settings.extend(Configuration::Settings)

    def self.enabled?
      Datadog.configuration.open_feature.enabled
    end

    def self.engine
      Datadog.send(:components).open_feature&.engine
    end
  end
end
