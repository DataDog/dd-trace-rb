require_relative '../../metadata/ext'
require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module Pubsub
        # Instrumentation for PubSub integration
        module Instrumentation
          # Instrumentation for Google::Cloud::PubSub::Topic
          module Publisher
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            # Instance methods for PubSub::Topic
            module InstanceMethods

              DD = ::Datadog::Tracing::Distributed::Datadog.new(fetcher: ::Datadog::Tracing::Distributed::Fetcher)
              private_constant :DD

              def publish(data = nil, attributes = nil, ordering_key: nil, compress: nil, compression_bytes_threshold: nil,
                          **extra_attrs, &block)
                Tracing.trace(
                  Ext::SPAN_SEND_MESSAGES,
                  service: datadog_configuration[:service_name]
                ) do |span|
                  attributes ||= {}
                  decorate!(span, attributes)
                  super(data, attributes, ordering_key: ordering_key, compress: compress, compression_bytes_threshold: compression_bytes_threshold,
                        **extra_attrs, &block)
                end
              end


              def datadog_configuration
                Datadog.configuration.tracing[:pubsub]
              end

              def decorate!(span, attributes)
                span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_MESSAGING_SYSTEM)
                span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PRODUCER)
                span.set_tag(Ext::TAG_TOPIC, self.name)

                span.resource = self.name

                # Set analytics sample rate
                if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
                  Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
                end

                DD.inject!(::Datadog::Tracing.active_trace.to_digest, attributes)
              end
            end
          end

          module Consumer
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            # Instance methods for PubSub::Topic
            module InstanceMethods

              DD = ::Datadog::Tracing::Distributed::Datadog.new(fetcher: ::Datadog::Tracing::Distributed::Fetcher)
              private_constant :DD

              def listen(deadline: nil, message_ordering: nil, streams: nil, inventory: nil, threads: {})
                traced_block = proc do |msg|
                  digest = DD.extract(msg.attributes || {})
                  ::Datadog::Tracing.trace(Ext::SPAN_RECEIVE_MESSAGES, continue_from: digest) do |span_op, _|
                    span_op.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_MESSAGING_SYSTEM)
                    span_op.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CONSUMER)

                    span_op.set_tag(Ext::TAG_TOPIC, self.topic.name)
                    span_op.set_tag(Ext::TAG_SUBSCRIPTION, self.name)
                    span_op.resource = self.name

                    yield msg
                  end
                end

                super(deadline: deadline, message_ordering: message_ordering, streams: streams, inventory: inventory, threads: threads, &traced_block)
              end
            end
          end
        end
      end
    end
  end
end
