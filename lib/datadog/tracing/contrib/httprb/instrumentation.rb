require_relative '../../metadata/ext'
require_relative '../../propagation/http'
require_relative '../analytics'
require_relative '../http_annotation_helper'

module Datadog
  module Tracing
    module Contrib
      module Httprb
        # Instrumentation for Httprb
        module Instrumentation
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # Instance methods for configuration
          module InstanceMethods
            include Contrib::HttpAnnotationHelper

            def perform(req, options)
              host = req.uri.host if req.respond_to?(:uri) && req.uri
              request_options = datadog_configuration(host)
              client_config = Datadog.configuration_for(self)

              Tracing.trace(Ext::SPAN_REQUEST, on_error: method(:annotate_span_with_error!)) do |span, trace|
                begin
                  span.service = service_name(host, request_options, client_config)
                  span.span_type = Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND

                  if Tracing.enabled? && !should_skip_distributed_tracing?(client_config)
                    Tracing::Propagation::HTTP.inject!(trace, req)
                  end

                  # Add additional request specific tags to the span.
                  annotate_span_with_request!(span, req, request_options)
                rescue StandardError => e
                  logger.error("error preparing span for http.rb request: #{e}, Source: #{e.backtrace}")
                ensure
                  res = super(req, options)
                end

                # Add additional response specific tags to the span.
                annotate_span_with_response!(span, res, request_options)

                res
              end
            end

            private

            def annotate_span_with_request!(span, req, req_options)
              span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)

              if req.verb && req.verb.is_a?(String) || req.verb.is_a?(Symbol)
                http_method = req.verb.to_s.upcase
                span.resource = http_method
                span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, http_method)
              else
                logger.debug("service #{req_options[:service_name]} span #{Ext::SPAN_REQUEST} missing request verb")
              end

              if req.uri
                uri = req.uri
                span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_URL, uri.path)
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, uri.host)
                span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, uri.port)

                span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, uri.host)
              else
                logger.debug("service #{req_options[:service_name]} span #{Ext::SPAN_REQUEST} missing uri")
              end

              # Tag as an external peer service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)

              set_analytics_sample_rate(span, req_options)
            end

            def annotate_span_with_response!(span, response, request_options)
              return unless response && response.code

              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, response.code)

              if request_options[:error_status_codes].include? response.code.to_i
                # https://github.com/DataDog/dd-trace-rb/issues/1116
                # parsing the response body message will alter downstream application behavior
                span.set_error(["Error #{response.code}", 'Error'])
              end
            end

            def annotate_span_with_error!(span, error)
              span.set_error(error)
            end

            def datadog_configuration(host = :default)
              Datadog.configuration.tracing[:httprb, host]
            end

            def analytics_enabled?(request_options)
              Contrib::Analytics.enabled?(request_options[:analytics_enabled])
            end

            def logger
              Datadog.logger
            end

            def should_skip_distributed_tracing?(client_config)
              return !client_config[:distributed_tracing] if client_config && client_config.key?(:distributed_tracing)

              !Datadog.configuration.tracing[:httprb][:distributed_tracing]
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
end
