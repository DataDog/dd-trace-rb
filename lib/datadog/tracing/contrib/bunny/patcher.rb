# frozen_string_literal: true

require_relative '../patcher'
require_relative 'instrumentation'
require 'opentelemetry/instrumentation/bunny'

module Datadog
  module Tracing
    module Contrib
      module Bunny
        # Patcher enables patching of 'trilogy' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            patch_trilogy_client
          end

          def patch_trilogy_client
            ::OpenTelemetry::Instrumentation::Bunny::Patches::Channel.prepend(Channel)
            ::OpenTelemetry::Instrumentation::Bunny::Patches::Consumer.prepend(Consumer)
            ::OpenTelemetry::Instrumentation::Bunny::Patches::Queue.prepend(Queue)
            ::OpenTelemetry::Instrumentation::Bunny::Patches::ReaderLoop.prepend(ReaderLoop)

            OpenTelemetry::Instrumentation::Bunny::Instrumentation.instance.install
          end

          module Channel
            def basic_publish(payload, exchange, routing_key, opts = {})
              OpenTelemetry::Instrumentation::Bunny::PatchHelpers.with_send_span(self, tracer, exchange, routing_key) do
                OpenTelemetry::Instrumentation::Bunny::PatchHelpers.inject_context_into_property(opts, :headers)

                super(payload, exchange, routing_key, opts)
              end
            end
          end

          module Consumer

          end
          module Queue

          end
          module ReaderLoop

          end
        end
      end
    end
  end
end
