# frozen_string_literal: true

require_relative "message_adapter"
require_relative "chat_instrumentation"

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # AIGuard patcher module for RubyLLM
        module Patcher
          def self.patched?
            !!Patcher.instance_variable_get(:@patched)
          end

          def self.target_version
            Integration.version
          end

          def self.patch
            ::RubyLLM::Chat.prepend(ChatInstrumentation)

            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
