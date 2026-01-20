# frozen_string_literal: true

require_relative "../integration"
require_relative "patcher"

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # This class provides helper methods that are used when patching RubyLLM
        class Integration
          include Datadog::AIGuard::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new("1.0.0")

          register_as :ruby_llm, auto_patch: false

          def self.version
            Gem.loaded_specs["ruby_llm"]&.version
          end

          def self.loaded?
            !defined?(::RubyLLM).nil?
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
