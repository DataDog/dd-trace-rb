# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Patches
          module LiveThreadPatch
            private

            def new_controller_thread
              context = Datadog::AppSec::Context.active
              return super unless context

              super do
                context.attach

                completed = false
                context.catch do
                  yield
                  completed = true
                end

                stream = response.stream
                stream.close if !completed && stream.is_a?(::ActionController::Live::Buffer) && !stream.closed?
              ensure
                context.detach
              end
            end
          end
        end
      end
    end
  end
end
