# frozen_string_literal: true

require_relative "core/configuration"
require_relative "open_feature/configuration"

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

    def self.activate_provider(provider)
      # Initialize the component tree before taking its reconfiguration lock.
      Datadog.send(:components)
      Datadog.send(:safely_synchronize) do
        components = Datadog.send(:components, allow_initialization: false)
        activation = components&.send(:open_feature_activation)
        @adopted_provider = provider
        [activation&.activate(provider), activation&.failure]
      end
    end

    def self.deactivate_provider(provider)
      Datadog.send(:safely_synchronize) do
        @adopted_provider = nil if @adopted_provider&.equal?(provider)
      end
    end

    # Components startup already holds the non-reentrant reconfiguration lock.
    def self.reattach(activation)
      provider = @adopted_provider
      activation.activate(provider) if provider
    end
  end
end
