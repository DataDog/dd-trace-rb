# typed: false
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/contrib/analytics'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/http_annotation_helper'

module Datadog
  module Contrib
    module Httpclient
      # Instrumentation for Httpclient
      module Instrumentation
        def self.included(base)
          base.prepend(InstanceMethods)
        end

        # Instance methods for configuration
        module InstanceMethods
          include Datadog::Contrib::HttpAnnotationHelper

          def do_get_block(req, proxy, conn, &block)
            host = req.header.request_uri.host
            request_options = datadog_configuration(host)
            client_config = Datadog::Tracing.configuration_for(self)

            Datadog::Tracing.trace(Ext::SPAN_REQUEST, on_error: method(:annotate_span_with_error!)) do |span, trace|
              begin
                span.service = service_name(host, request_options, client_config)
                span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND

                if Datadog::Tracing.enabled? && !should_skip_distributed_tracing?(client_config)
                  Datadog::HTTPPropagator.inject!(trace, req.header)
                end

                # Add additional request specific tags to the span.
                annotate_span_with_request!(span, req, request_options)
              rescue StandardError => e
                logger.error("error preparing span for httpclient request: #{e}, Source: #{e.backtrace}")
              ensure
                res = super
              end

              # Add additional response specific tags to the span.
              annotate_span_with_response!(span, res)

              res
            end
          end

          private

          def annotate_span_with_request!(span, req, req_options)
            span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)

            http_method = req.header.request_method.upcase
            uri = req.header.request_uri

            span.resource = http_method
            span.set_tag(Datadog::Ext::HTTP::METHOD, http_method)
            span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)

            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_SERVICE, span.service)
            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_HOSTNAME, uri.host)

            set_analytics_sample_rate(span, req_options)
          end

          def annotate_span_with_response!(span, response)
            return unless response && response.status

            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.status)

            case response.status.to_i
            when 400...599
              span.set_error(["Error #{response.status}", response.body])
            end
          end

          def annotate_span_with_error!(span, error)
            span.set_error(error)
          end

          def datadog_configuration(host = :default)
            Datadog::Tracing.configuration[:httpclient, host]
          end

          def analytics_enabled?(request_options)
            Contrib::Analytics.enabled?(request_options[:analytics_enabled])
          end

          def logger
            Datadog.logger
          end

          def should_skip_distributed_tracing?(client_config)
            return !client_config[:distributed_tracing] if client_config && client_config.key?(:distributed_tracing)

            !Datadog::Tracing.configuration[:httpclient][:distributed_tracing]
          end

          def set_analytics_sample_rate(span, request_options)
            return unless analytics_enabled?(request_options)

            Contrib::Analytics.set_sample_rate(span, request_options[:analytics_sample_rate])
          end
        end
      end
    end
  end
end
