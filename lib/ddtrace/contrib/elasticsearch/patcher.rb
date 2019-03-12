require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/net'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/elasticsearch/ext'

module Datadog
  module Contrib
    module Elasticsearch
      # Patcher enables patching of 'elasticsearch' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:elasticsearch)
        end

        def patch
          do_once(:elasticsearch) do
            begin
              require 'uri'
              require 'json'
              require 'ddtrace/pin'
              require 'ddtrace/contrib/elasticsearch/quantize'

              patch_elasticsearch_transport_client
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Elasticsearch integration: #{e}")
            end
          end
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        def patch_elasticsearch_transport_client
          # rubocop:disable Metrics/BlockLength
          ::Elasticsearch::Transport::Client.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Patcher.without_warnings do
              remove_method :initialize
            end

            def initialize(*args, &block)
              tracer = Datadog.configuration[:elasticsearch][:tracer]
              service = Datadog.configuration[:elasticsearch][:service_name]

              pin = Datadog::Pin.new(
                service,
                app: Datadog::Contrib::Elasticsearch::Ext::APP,
                app_type: Datadog::Ext::AppTypes::DB,
                tracer: tracer
              )
              pin.onto(self)
              initialize_without_datadog(*args, &block)
            end

            alias_method :perform_request_without_datadog, :perform_request
            remove_method :perform_request

            def perform_request(*args)
              pin = Datadog::Pin.get_from(self)
              return perform_request_without_datadog(*args) unless pin && pin.tracer

              method = args[0]
              path = args[1]
              params = args[2]
              body = args[3]
              full_url = URI.parse(path)

              url = full_url.path
              response = nil
              pin.tracer.trace(Datadog::Contrib::Elasticsearch::Ext::SPAN_QUERY) do |span|
                begin
                  connection = transport.connections.first
                  host = connection.host[:host] if connection
                  port = connection.host[:port] if connection

                  span.service = pin.service
                  span.span_type = Datadog::Ext::AppTypes::DB

                  # load JSON for the following fields unless they're already strings
                  params = JSON.generate(params) if params && !params.is_a?(String)
                  body = JSON.generate(body) if body && !body.is_a?(String)

                  # Set analytics sample rate
                  if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
                    Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
                  end

                  span.set_tag(Datadog::Contrib::Elasticsearch::Ext::TAG_METHOD, method)
                  span.set_tag(Datadog::Contrib::Elasticsearch::Ext::TAG_URL, url)
                  span.set_tag(Datadog::Contrib::Elasticsearch::Ext::TAG_PARAMS, params) if params
                  if body
                    quantize_options = datadog_configuration[:quantize]
                    quantized_body = Datadog::Contrib::Elasticsearch::Quantize.format_body(body, quantize_options)
                    span.set_tag(Datadog::Contrib::Elasticsearch::Ext::TAG_BODY, quantized_body)
                  end
                  span.set_tag(Datadog::Ext::NET::TARGET_HOST, host) if host
                  span.set_tag(Datadog::Ext::NET::TARGET_PORT, port) if port

                  quantized_url = Datadog::Contrib::Elasticsearch::Quantize.format_url(url)
                  span.resource = "#{method} #{quantized_url}"
                rescue StandardError => e
                  Datadog::Tracer.log.error(e.message)
                ensure
                  # the call is still executed
                  response = perform_request_without_datadog(*args)
                  span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.status)
                end
              end
              response
            end

            def datadog_configuration
              Datadog.configuration[:elasticsearch]
            end
          end
        end
      end
    end
  end
end
