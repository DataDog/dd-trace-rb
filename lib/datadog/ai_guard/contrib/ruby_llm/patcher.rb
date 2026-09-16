# frozen_string_literal: true

require_relative "message_converter"
require_relative "message_redactor"
require_relative "chat_instrumentation"
require_relative "provider_instrumentation"

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # AIGuard patcher module for RubyLLM
        module Patcher
          module_function

          def patched?
            !!Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            ::RubyLLM::Chat.prepend(ChatInstrumentation)
            ::RubyLLM::Provider.prepend(ProviderInstrumentation)

            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
