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
          # Defines instrumentation for 'service_download_chunk.active_storage' event.
          #
          # TODO: Define
          module DownloadChunk
            include ActiveStorage::Event

            EVENT_NAME = 'service_download_chunk.active_storage'.freeze

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
              Ext::ACTION_DOWNLOAD_CHUNK
            end

            def process(span, _event, _id, payload)
              as_key = payload[:key]
              as_service = payload[:service]
              as_range = payload[:range]

              span.service = configuration[:service_name]
              span.resource = "#{resource_prefix} #{as_service}"
              span.span_type = span_type

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

              span.set_tag(Ext::TAG_SERVICE, as_service)
              span.set_tag(Ext::TAG_KEY, as_key)
              span.set_tag(Ext::TAG_RANGE, as_range)
            end
          end
        end
      end
    end
  end
end
