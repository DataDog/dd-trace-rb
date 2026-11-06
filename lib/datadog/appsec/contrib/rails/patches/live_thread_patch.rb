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

                interrupted = context.catch_interrupt { yield }

                stream = response.stream
                stream.close if interrupted && stream.is_a?(::ActionController::Live::Buffer) && !stream.closed?
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
