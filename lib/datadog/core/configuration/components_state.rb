# frozen_string_literal: true

module Datadog
  module Core
    module Configuration
      # Stores the state of component tree when replacing the tree.
      class ComponentsState
        def initialize(telemetry_enabled:, remote_started:, di_implicitly_enabled: false,
          rc_enablement_signal_paths: [])
          @telemetry_enabled = !!telemetry_enabled
          @remote_started = !!remote_started
          @di_implicitly_enabled = !!di_implicitly_enabled
          @rc_enablement_signal_paths = rc_enablement_signal_paths || []
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

        # The repository paths of the APM_TRACING configs that supplied the
        # dynamic_instrumentation_enabled value at the last merge where the
        # field was present, carried over from the replaced tree's DI
        # component so a withdrawn enable signal is still recognized after
        # a rebuild.
        #
        # @return [Array[Core::Remote::Configuration::Path]] the recorded
        #   enable-signal carrier paths
        attr_reader :rc_enablement_signal_paths
      end
    end
  end
end
