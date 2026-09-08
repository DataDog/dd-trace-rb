# frozen_string_literal: true

module Datadog
  module Core
    module Configuration
      # Stores the state of component tree when replacing the tree.
      class ComponentsState
        attr_reader :open_feature_provider

        def initialize(telemetry_enabled:, remote_started:, di_implicitly_enabled: false, open_feature_provider: nil)
          @telemetry_enabled = !!telemetry_enabled
          @remote_started = !!remote_started
          @di_implicitly_enabled = !!di_implicitly_enabled
          @open_feature_provider = open_feature_provider
        end

        def telemetry_enabled?
          @telemetry_enabled
        end

        def remote_started?
          @remote_started
        end

        def di_implicitly_enabled?
          @di_implicitly_enabled
        end
      end
    end
  end
end
