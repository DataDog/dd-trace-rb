# frozen_string_literal: true

require_relative 'core/configuration'
require_relative 'ai_guard/configuration'

module Datadog
  # A namespace for the AI Guard component.
  module AIGuard
    Core::Configuration::Settings.extend(Configuration::Settings)

    def self.enabled?
      Datadog.configuration.ai_guard.enabled
    end
  end
end
