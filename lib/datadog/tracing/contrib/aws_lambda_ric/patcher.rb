# frozen_string_literal: true

require_relative "../patcher"

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        # Installs instrumentation at the RIC boundary around the user handler.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require_relative "instrumentation"

            ::LambdaHandler.prepend(Instrumentation)
            Datadog.configuration.appsec.instrument(:aws_lambda)
          end
        end
      end
    end
  end
end
