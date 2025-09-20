# frozen_string_literal: true

require_relative '../patcher'
require_relative 'ext'
require_relative 'distributed/propagation'

module Datadog
  module Tracing
    module Contrib
      module Karafka
        # Patch to add tracing to Karafka::Messages::Messages
        module MessagesPatch
          def configuration
            Datadog.configuration.tracing[:karafka]
          end

          def propagation
            @propagation ||= Contrib::Karafka::Distributed::Propagation.new
          end

          # `each` is the most popular access point to Karafka messages,
          # but not the only one
          #  Other access patterns do not have a straightforward tracing avenue
          # (e.g. `my_batch_operation messages.payloads`)
          # @see https://github.com/karafka/karafka/blob/b06d1f7c17818e1605f80c2bb573454a33376b40/README.md?plain=1#L29-L35
          def each(&block)
            parent_span = Datadog::Tracing.active_span
            parent_trace_digest = Datadog::Tracing.active_trace&.to_digest

            @messages_array.each do |message|
              trace_digest = if configuration[:distributed_tracing]
                               headers = if message.metadata.respond_to?(:raw_headers)
                                           message.metadata.raw_headers
                                         else
                                           message.metadata.headers
                                         end
                               Karafka.extract(headers)
                             end

              Tracing.trace(Ext::SPAN_MESSAGE_CONSUME, continue_from: trace_digest) do |span, trace|
                span.set_tag(Ext::TAG_OFFSET, message.metadata.offset)
                span.set_tag(Contrib::Ext::Messaging::TAG_DESTINATION, message.topic)
                span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Ext::TAG_SYSTEM)

                span.resource = message.topic

                # link the outer trace (where the messages batch was consumed)
                # with the individual message's processing trace, so they're easier to
                # correlate in the Datadog UI
                if parent_span && span.parent_id != parent_span.id
                  # add a link from the parent trace to the message span
                  span_link = Tracing::SpanLink.new(parent_trace_digest)
                  span.links << span_link

                  # add a link from the current trace to the parent span
                  span_link = Tracing::SpanLink.new(trace.to_digest)
                  parent_span.links << span_link
                end

                yield message
              end
            end
          end
        end

        # Patcher enables patching of 'karafka' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require_relative 'monitor'

            ::Karafka::Instrumentation::Monitor.prepend(Monitor)
            ::Karafka::Messages::Messages.prepend(MessagesPatch)
          end
        end
      end
    end
  end
end
