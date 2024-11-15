# frozen_string_literal: true

require_relative '../patcher'
require_relative 'events'
require_relative 'ext'
require_relative 'distributed/propagation'

module Datadog
  module Tracing
    module Contrib
      module Karafka
        module MessagesPatch
          def configuration
            Datadog.configuration.tracing[:sidekiq]
          end

          def propagation
            @propagation ||= Contrib::Sidekiq::Distributed::Propagation.new
          end

          def each(&block)
            @messages_array.each do |message|
              if configuration[:distributed_tracing]
                trace_digest = Karafka.extract(message.metadata.headers)
                Datadog::Tracing.continue_trace!(trace_digest) if trace_digest
              end

              Tracing.trace(Ext::SPAN_MESSAGE_CONSUME) do |span|
                span.set_tag(Ext::TAG_OFFSET, message.metadata.offset)
                span.set_tag(Ext::TAG_TOPIC, message.topic)

                span.resource = message.topic

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
            Events.subscribe!

            ::Karafka::Messages::Messages.prepend(MessagesPatch)
          end
        end
      end
    end
  end
end
