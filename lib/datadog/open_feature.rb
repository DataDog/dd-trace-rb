# frozen_string_literal: true

require_relative 'open_feature/extensions'

module Datadog
  # A namespace for the OpenFeature component.
  module OpenFeature
    Extensions.activate!

    def self.enabled?
      Datadog.configuration.open_feature.enabled
    end

    def self.engine
      Datadog.send(:components).open_feature&.engine
    end
  end
end
