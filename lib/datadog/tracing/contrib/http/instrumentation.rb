# frozen_string_literal: true

require "uri"

require_relative "../../metadata/ext"
require_relative "../analytics"
require_relative "../http_annotation_helper"
require_relative "../utils/quantization/http"
require_relative "../../../core/telemetry/logger"

module Datadog
  module Tracing
    module Contrib
      module HTTP
        # Instrumentation for Net::HTTP
        module Instrumentation
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # InstanceMethods - implementing instrumentation
          module InstanceMethods
            include Contrib::HttpAnnotationHelper

            # :yield: +response+
            def request(req, body = nil, &block)
              host, = host_and_port(req)
              request_options = datadog_configuration(host)
              client_config = Datadog.configuration_for(self)

              return super if Contrib::HTTP.should_skip_tracing?(req)

              Tracing.trace(Ext::SPAN_REQUEST, type: Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND) do |span, trace|
                annotate_span_with_service!(span, host, request_options, client_config)
                quantize_resource = Datadog.configuration.tracing.http_client_resource_name_quantize
                span.resource = Contrib::Utils::Quantization::HTTP.client_resource(
                  req.method,
                  quantize_resource ? request_uri_path(req) : nil,
                  enabled: quantize_resource,
                )

                if Tracing::Distributed::PropagationPolicy.enabled?(
                  pin_config: client_config,
                  global_config: request_options,
                  trace: trace,
                )
                  Contrib::HTTP.inject(trace, req)
                end

                # Add additional request specific tags to the span.
                annotate_span_with_request!(span, req, request_options)

                response = super(req, body, &block)

                # Add additional response specific tags to the span.
                annotate_span_with_response!(span, response, request_options)

                response
              end
            end

            def annotate_span_with_request!(span, request, request_options)
              host, port = host_and_port(request)
              annotate_client_span!(span, Ext::TAG_OPERATION_REQUEST, host, port, request_options)

              span.set_tag(
                Tracing::Metadata::Ext::HTTP::TAG_URL,
                Contrib::Utils::Quantization::HTTP.url(request.path, {query: {exclude: :all}}),
              )
              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, request.method)

              span.set_tags(
                Datadog.configuration.tracing.header_tags.request_tags(request),
              )

              Contrib::SpanAttributeSchema.set_peer_service!(span, Ext::PEER_SERVICE_SOURCES)
            rescue => e
              report_annotation_error("request", e)
            end

            def annotate_span_with_response!(span, response, request_options)
              return unless response&.code

              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, response.code)

              span.set_error(response) if request_options[:error_status_codes].include? response.code.to_i

              span.set_tags(
                Datadog.configuration.tracing.header_tags.response_tags(response),
              )
            rescue => e
              report_annotation_error("response", e)
            end

            def set_analytics_sample_rate(span, request_options)
              return unless analytics_enabled?(request_options)

              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate(request_options))
            end

            private

            # Traces connection setup.
            #
            # Net::HTTP declares +connect+ as private; the override keeps that visibility.
            def connect
              return super unless connection_traceable?

              request_options = datadog_configuration(address)
              client_config = Datadog.configuration_for(self)

              Tracing.trace(Ext::SPAN_CONNECT, type: Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND) do |span|
                annotate_span_with_connection!(span, request_options, client_config)

                super
              end
            end

            # Connections made by Datadog's own transports are excluded: they run on worker
            # threads with no active trace, or, with Tracing::SyncWriter, on the application
            # thread while the just-finished trace is still active.
            def connection_traceable?
              trace = Tracing.active_trace
              !trace.nil? && !trace.finished?
            end

            def annotate_span_with_connection!(span, request_options, client_config)
              annotate_span_with_service!(span, address, request_options, client_config)
              span.resource = address
              annotate_client_span!(span, Ext::TAG_OPERATION_CONNECT, address, port, request_options)

              Contrib::SpanAttributeSchema.set_peer_service!(span, Ext::PEER_SERVICE_SOURCES)
            rescue => e
              report_annotation_error("connection", e)
            end

            def annotate_span_with_service!(span, host, request_options, client_config)
              span.service = service_name(host, request_options, client_config)
              span.set_tag(Tracing::Metadata::Ext::TAG_SVC_SRC, Ext::TAG_COMPONENT)
            end

            def annotate_client_span!(span, operation, host, port, request_options)
              if request_options[:peer_service]
                span.set_tag(
                  Tracing::Metadata::Ext::TAG_PEER_SERVICE,
                  request_options[:peer_service],
                )
              end

              span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, operation)

              span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, host)
              span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, port.to_s)

              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, host)

              set_analytics_sample_rate(span, request_options)
            end

            def report_annotation_error(annotated_object, error)
              Datadog.logger.error("error preparing span from http #{annotated_object}: #{error.class}: #{error.message}")
              Datadog::Core::Telemetry::Logger.report(error)
            end

            def request_uri_path(request)
              uri = request.uri if request.respond_to?(:uri)
              return uri.path if uri
              return request.path.split(/[?#]/, 2).first if request.path.start_with?("/")

              URI.parse(request.path).path
            rescue URI::InvalidURIError
              nil
            end

            def host_and_port(request)
              if request.respond_to?(:uri) && request.uri
                [request.uri.host, request.uri.port]
              else
                [address, port]
              end
            end

            def datadog_configuration(host = :default)
              Datadog.configuration.tracing[:http, host]
            end

            def analytics_enabled?(request_options)
              Contrib::Analytics.enabled?(request_options[:analytics_enabled])
            end

            def analytics_sample_rate(request_options)
              request_options[:analytics_sample_rate]
            end
          end
        end
      end
    end
  end
end
