# frozen_string_literal: true

module Datadog
  module AppSec
    # AppSec-specific environment adjustments applied at load time.
    module Env
      AWS_LAMBDA_FUNCTION_NAME = 'AWS_LAMBDA_FUNCTION_NAME'
      DD_APPSEC_ENABLED = 'DD_APPSEC_ENABLED'

      module_function

      def disable_appsec_on_lambda!
        return unless Datadog::DATADOG_ENV.key?(AWS_LAMBDA_FUNCTION_NAME)

        # AppSec is not supported on AWS Lambda; force-disable via env so autoload and
        # configuration resolution both see AppSec as disabled.
        # rubocop:disable CustomCops/EnvUsageCop -- intentional ENV override for config inversion
        ENV[DD_APPSEC_ENABLED] = 'false'
        # rubocop:enable CustomCops/EnvUsageCop
      end
    end
  end
end
