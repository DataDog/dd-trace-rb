# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module RestClient
        # Patcher for RestClient gem
        module Patcher
          def self.patched?
            !!Patcher.instance_variable_get(:@patched)
          end

          def self.target_version
            Integration.version
          end

          def self.patch
            require_relative "request_ssrf_detection_patch"

            ::RestClient::Request.prepend(RequestSSRFDetectionPatch)

            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
