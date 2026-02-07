# frozen_string_literal: true

require_relative '../../../metadata/ext'
require_relative '../event'
require_relative '../ext'
require_relative '../../analytics'

module Datadog
  module Tracing
    module Contrib
      module ActiveStorage
        module Events
          # Defines instrumentation for 'transform.active_storage' event.
          #
          # A transform operation was performed against a blob hosted on the remote service
          module Transform
            include ActiveStorage::Event

            EVENT_NAME = 'transform.active_storage'.freeze

            module_function

            def event_name
              self::EVENT_NAME
            end

            def span_name
              Ext::SPAN_TRANSFORM
            end

            def span_type
              # Interacting with a cloud-based blob service via HTTP
              Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND
            end

            def process(span, _event, _id, payload)
              # transform contains no payload details
              # https://edgeguides.rubyonrails.org/active_support_instrumentation.html#transform-active-storage

              span.service = configuration[:service_name] if configuration[:service_name]
              span.span_type = span_type

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_TRANSFORM)
            end
          end
        end
      end
    end
  end
end
