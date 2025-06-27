# frozen_string_literal: true

require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        # Description of AWS Lambda RIC integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('3.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :aws_lambda_ric, auto_patch: true
          def self.gem_name
            'aws_lambda_ric'
          end

          def self.version
            Gem.loaded_specs['aws_lambda_ric'].version if Gem.loaded_specs['aws_lambda_ric']
          end

          def self.loaded?
            !defined?(::AwsLambdaRIC).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
