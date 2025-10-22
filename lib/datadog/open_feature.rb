# frozen_string_literal: true

require_relative 'open_feature/extensions'

module Datadog
  module OpenFeature
    Extensions.activate!

    def self.enabled?
      Datadog.configuration.open_feature.enabled
    end

    def self.component
      Datadog.send(:components).open_feature
    end
  end
end
