# typed: false
require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/elasticsearch/ext'
require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/patcher'

module Datadog
  module Tracing
    module Contrib
      module Elasticsearch
        # Patcher enables patching of 'elasticsearch' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require 'uri'
            require 'json'
            require 'datadog/tracing/contrib/elasticsearch/quantize'

            patch_elasticsearch_transport_client
          end

          # rubocop:disable Metrics/MethodLength
          # rubocop:disable Metrics/AbcSize
          def patch_elasticsearch_transport_client
            # rubocop:disable Metrics/BlockLength
            ::Elasticsearch::Transport::Client.class_eval do
              alias_method :perform_request_without_datadog, :perform_request
              remove_method :perform_request

              def perform_request(*args)
                service = Datadog.configuration_for(self, :service_name) || datadog_configuration[:service_name]

                method = args[0]
                path = args[1]
                params = args[2]
                body = args[3]
                full_url = URI.parse(path)

                url = full_url.path
                response = nil

                Tracing.trace(Datadog::Tracing::Contrib::Elasticsearch::Ext::SPAN_QUERY, service: service) do |span|
                  begin
                    connection = transport.connections.first
                    host = connection.host[:host] if connection
                    port = connection.host[:port] if connection

                    span.span_type = Datadog::Tracing::Contrib::Elasticsearch::Ext::SPAN_TYPE_QUERY

                    span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
                    span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_QUERY)

                    # load JSON for the following fields unless they're already strings
                    params = JSON.generate(params) if params && !params.is_a?(String)
                    body = JSON.generate(body) if body && !body.is_a?(String)

                    # Tag as an external peer service
                    span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)
                    span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, host) if host

                    # Set analytics sample rate
                    if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
                      Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
                    end

                    span.set_tag(Datadog::Tracing::Contrib::Elasticsearch::Ext::TAG_METHOD, method)
                    span.set_tag(Datadog::Tracing::Contrib::Elasticsearch::Ext::TAG_URL, url)
                    span.set_tag(Datadog::Tracing::Contrib::Elasticsearch::Ext::TAG_PARAMS, params) if params
                    if body
                      quantize_options = datadog_configuration[:quantize]
                      quantized_body = Datadog::Tracing::Contrib::Elasticsearch::Quantize.format_body(
                        body,
                        quantize_options
                      )
                      span.set_tag(Datadog::Tracing::Contrib::Elasticsearch::Ext::TAG_BODY, quantized_body)
                    end
                    span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, host) if host
                    span.set_tag(Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, port) if port

                    quantized_url = Datadog::Tracing::Contrib::Elasticsearch::Quantize.format_url(url)
                    span.resource = "#{method} #{quantized_url}"
                  rescue StandardError => e
                    Datadog.logger.error(e.message)
                  ensure
                    # the call is still executed
                    response = perform_request_without_datadog(*args)
                    span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, response.status)
                  end
                end
                response
              end

              def datadog_configuration
                Tracing.configuration.tracing[:elasticsearch]
              end
            end
            # rubocop:enable Metrics/BlockLength
          end
          # rubocop:enable Metrics/MethodLength
          # rubocop:enable Metrics/AbcSize
        end
      end
    end
  end
end
