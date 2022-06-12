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
          # Defines instrumentation for 'service_delete_prefixed.active_storage' event.
          #
          # Blobs with names beginning with the given prefix were deleted
          module DeletePrefixed
            include ActiveStorage::Event

            EVENT_NAME = 'service_delete_prefixed.active_storage'.freeze

            module_function

            def event_name
              self::EVENT_NAME
            end

            def span_name
              Ext::SPAN_DELETE_PREFIXED
            end

            def span_type
              # Interacting with a cloud-based blob service via HTTP
              Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND
            end

            def process(span, _event, _id, payload)
              as_prefix = payload[:prefix]
              as_service = payload[:service]

              span.service = configuration[:service_name] if configuration[:service_name]
              span.resource = "#{as_service}: #{as_prefix}"
              span.span_type = span_type

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

              span.set_tag(Ext::TAG_SERVICE, as_service)
              span.set_tag(Ext::TAG_PREFIX, as_prefix)
            end
          end
        end
      end
    end
  end
end
