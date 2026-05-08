# frozen_string_literal: true

require_relative 'patcher'
require_relative '../integration'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        class Integration
          include Datadog::AppSec::Contrib::Integration

          register_as :aws_lambda, auto_patch: false

          # NOTE: AWS Lambda is a runtime environment, not an installable gem
          def self.version
            nil
          end

          def self.loaded?
            true
          end

          def self.compatible?
            super
          end

          def self.auto_instrument?
            false
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
