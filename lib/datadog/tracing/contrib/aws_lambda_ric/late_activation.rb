# frozen_string_literal: true

require_relative "../../../core/utils/only_once"

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        # Activates integrations loaded by the user's handler file after auto-instrumentation booted.
        module LateActivation
          PATCH_ONCE = Core::Utils::OnlyOnce.new

          module_function

          def patch!
            PATCH_ONCE.run do
              Datadog.configuration.tracing.instrumented_integrations.each_value(&:patch)
              if defined?(Datadog::AppSec::Contrib::AutoInstrument)
                Datadog::AppSec::Contrib::AutoInstrument.patch_all
              end
            end
          rescue => e
            Datadog.logger.debug { "Failed to activate Lambda handler integrations: #{e.class}: #{e.message}" }
          end
        end
      end
    end
  end
end
