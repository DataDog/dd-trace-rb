# frozen_string_literal: true

module Datadog
  module Core
    module Configuration
      # Stores the state of component tree when replacing the tree.
      class ComponentsState
        def initialize(telemetry_enabled:, remote_started:, di_implicitly_enabled: false, open_feature_activated: false)
          @telemetry_enabled = !!telemetry_enabled
          @remote_started = !!remote_started
          @di_implicitly_enabled = !!di_implicitly_enabled
          @open_feature_activated = !!open_feature_activated
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

        def open_feature_activated?
          @open_feature_activated
        end
      end
    end
  end
end
