# frozen_string_literal: true

require_relative '../patcher'
require_relative 'instrumentation'

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        # Patcher enables patching of 'aws_lambda_ric' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            patch_lambda_runner
            patch_lambda_handler
          end

          def patch_lambda_runner
            return unless defined?(::AwsLambdaRIC::LambdaRunner)

            ::AwsLambdaRIC::LambdaRunner.include(Instrumentation)
          rescue StandardError => e
            Datadog.logger.debug("Unable to patch AwsLambdaRIC::LambdaRunner: #{e}")
          end

          def patch_lambda_handler
            return unless defined?(::AwsLambdaRIC::LambdaHandler)

            ::AwsLambdaRIC::LambdaHandler.include(Instrumentation)
          rescue StandardError => e
            Datadog.logger.debug("Unable to patch AwsLambdaRIC::LambdaHandler: #{e}")
          end
        end
      end
    end
  end
end
