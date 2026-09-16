# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # module that gets prepended to RubyLLM::Chat
        module ChatInstrumentation
          def handle_tool_calls(response, &block)
            AIGuard.evaluate(*MessageConverter.convert(messages))

            super
          end
        end
      end
    end
  end
end
