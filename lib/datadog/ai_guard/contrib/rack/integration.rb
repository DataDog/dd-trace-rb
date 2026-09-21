# frozen_string_literal: true

require_relative "../integration"
require_relative "patcher"
require_relative "request_middleware"

module Datadog
  module AIGuard
    module Contrib
      module Rack
        # Rack integration for AI Guard
        class Integration
          include Datadog::AIGuard::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new("1.1.0")

          register_as :rack, auto_patch: false

          def self.version
            Gem.loaded_specs["rack"]&.version
          end

          def self.loaded?
            !defined?(::Rack).nil?
          end

          def self.compatible?
            super && !!(version&.>= MINIMUM_VERSION)
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
