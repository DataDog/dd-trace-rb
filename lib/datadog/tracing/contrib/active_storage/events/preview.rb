# typed: false

require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/active_storage/event'
require 'datadog/tracing/contrib/active_storage/ext'
require 'datadog/tracing/contrib/analytics'

module Datadog
  module Tracing
    module Contrib
      module ActiveStorage
        module Events
          # Defines instrumentation for 'preview.active_storage' event.
          #
          # TODO: Define
          module Preview
            include ActiveStorage::Event

            EVENT_NAME = 'preview.active_storage'.freeze

            module_function

            def event_name
              self::EVENT_NAME
            end

            def span_name
              Ext::SPAN_ACTION
            end

            def span_type
              # Interacting with a cloud based image service
              Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND
            end

            def resource_prefix
              Ext::ACTION_PREVIEW
            end

            def process(span, _event, _id, payload)
              as_key = payload[:key]

              span.service = configuration[:service_name]
              # preview action is not specific to a service and key cardinality is too high for a resource
              # so just use resource prefix
              # https://edgeguides.rubyonrails.org/active_support_instrumentation.html#preview-active-storage
              span.resource = resource_prefix
              span.span_type = span_type

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

              span.set_tag(Ext::TAG_KEY, as_key)
            end
          end
        end
      end
    end
  end
end
