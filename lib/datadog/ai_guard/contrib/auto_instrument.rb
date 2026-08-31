# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      # Auto-instrumentation for AI Guard integrations
      module AutoInstrument
        def self.patch_all
          integrations = []

          Datadog::AIGuard::Contrib::Integration.registry.each_value do |integration|
            next unless integration.klass.auto_instrument?

            integrations << integration.name
          end

          integrations.each do |integration_name|
            Datadog.configuration.ai_guard.instrument(integration_name)
          end
        end
      end
    end
  end
end
