# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Excon
        # AppSec patcher module for Excon
        module Patcher
          def self.patched?
            !!Patcher.instance_variable_get(:@patched)
          end

          def self.target_version
            Integration.version
          end

          def self.patch
            require_relative "ssrf_detection_middleware"

            ::Excon.defaults[:middlewares].insert(0, SSRFDetectionMiddleware)

            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
