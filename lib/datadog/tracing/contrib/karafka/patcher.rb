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
          # `each` is the most popular access point to Karafka messages,
          # but not the only one
          #  Other access patterns do not have a straightforward tracing avenue
          # (e.g. `my_batch_operation messages.payloads`)
          # @see https://github.com/karafka/karafka/blob/b06d1f7c17818e1605f80c2bb573454a33376b40/README.md?plain=1#L29-L35
          def each(&block)
            @messages_array.each do |message|
              configuration = datadog_configuration(message.topic)
              trace_digest = if configuration[:distributed_tracing]
                headers = if message.metadata.respond_to?(:raw_headers)
                  message.metadata.raw_headers
                else
                  message.metadata.headers
                end
                Karafka.extract(headers)
              end

              Tracing.trace(Ext::SPAN_MESSAGE_CONSUME, continue_from: trace_digest) do |span, trace|
                if Datadog::DataStreams.enabled?
                  begin
                    headers = if message.metadata.respond_to?(:raw_headers)
                      message.metadata.raw_headers
                    else
                      message.metadata.headers
                    end

                    Datadog::DataStreams.set_consume_checkpoint(
                      type: 'kafka',
                      source: message.topic,
                      auto_instrumentation: true
                    ) { |key| headers[key] }
                  rescue => e
                    Datadog.logger.debug("Error setting DSM checkpoint: #{e.class}: #{e}")
                  end
                end

                span.set_tag(Ext::TAG_OFFSET, message.metadata.offset)
                span.set_tag(Contrib::Ext::Messaging::TAG_DESTINATION, message.topic)
                span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Ext::TAG_SYSTEM)

                span.resource = message.topic

                yield message
              end
            end
          end

          private

          def datadog_configuration(topic)
            Datadog.configuration.tracing[:karafka, topic]
          end
        end

        module AppPatch
          ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Core::Utils::OnlyOnce.new }

          def initialized!
            ONLY_ONCE_PER_APP[self].run do
              # Activate tracing on components related to Karafka (e.g. WaterDrop)
              Contrib::Karafka::Framework.setup
            end
            super
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
            require_relative 'framework'

            ::Karafka::Instrumentation::Monitor.prepend(Monitor)
            ::Karafka::Messages::Messages.prepend(MessagesPatch)
            ::Karafka::App.singleton_class.prepend(AppPatch)
          end
        end
      end
    end
  end
end
