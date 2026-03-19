# frozen_string_literal: true

require_relative '../integration'
require_relative 'patcher'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        class Integration
          include Datadog::AppSec::Contrib::Integration

          register_as :aws_lambda, auto_patch: false

          def self.version
            nil
          end

          def self.loaded?
            true
          end

          def self.compatible?
            true
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
