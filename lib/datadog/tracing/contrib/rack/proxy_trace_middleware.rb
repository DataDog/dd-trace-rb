require 'date'

require_relative '../../../core/environment/variable_helpers'
require_relative '../../../core/backport'
require_relative '../../client_ip'
require_relative '../../metadata/ext'
require_relative '../../propagation/http'
require_relative '../analytics'
require_relative '../utils/quantization/http'
require_relative 'ext'
require_relative 'header_collection'
require_relative 'header_tagging'
require_relative 'request_queue'

module Datadog
  module Tracing
    module Contrib
      module Rack
        module ProxyTraceMiddleware
          module_function

          def call(env, configuration)
            return yield unless configuration[:request_queuing]

            # parse the request queue time
            request_start = Contrib::Rack::QueueTime.get_request_start(env)
            return yield unless request_start

            case configuration[:request_queuing]
            when :include_request

              options = {
                service: configuration[:web_service_name],
                start_time: request_start,
                span_type: Tracing::Metadata::Ext::HTTP::TYPE_PROXY
              }

              queue_span = Tracing.trace(Ext::SPAN_HTTP_SERVER_QUEUE, **options)
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_SERVER_QUEUE)
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_SERVER)

              yield.tap { queue_span.finish }
            when :exclude_request
              options = {
                service: configuration[:web_service_name],
                start_time: request_start,
                span_type: Tracing::Metadata::Ext::HTTP::TYPE_PROXY
              }

              request_span = Tracing.trace(Ext::SPAN_HTTP_PROXY_REQUEST, **options)

              request_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT_HTTP_PROXY)
              request_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_PROXY_REQUEST)
              request_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PROXY)

              queue_span = Tracing.trace(Ext::SPAN_HTTP_PROXY_QUEUE, **options)

              queue_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT_HTTP_PROXY)
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_PROXY_QUEUE)
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PROXY)

              Contrib::Analytics.set_measured(queue_span)
              # finish the `queue` span now to record only the time spent *in queue*,
              # excluding the time spent processing the request itself
              queue_span.finish

              yield.tap { request_span.finish }
            end
          end
        end
      end
    end
  end
end
