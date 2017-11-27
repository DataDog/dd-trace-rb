# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module Elasticsearch
      URL = 'elasticsearch.url'.freeze
      METHOD = 'elasticsearch.method'.freeze
      PARAMS = 'elasticsearch.params'.freeze
      BODY = 'elasticsearch.body'.freeze

      SERVICE = 'elasticsearch'.freeze
      SPAN_TYPE = 'elasticsearch'.freeze

      # Patcher enables patching of 'elasticsearch/transport' module.
      # This is used in monkey.rb to automatically apply patches
      module Patcher
        include Base
        register_as :elasticsearch, auto_patch: true
        option :service_name, default: SERVICE

        @patched = false

        module_function

        # patch applies our patch if needed
        def patch
          if !@patched && (defined?(::Elasticsearch::Transport::VERSION) && \
                           Gem::Version.new(::Elasticsearch::Transport::VERSION) >= Gem::Version.new('1.0.0'))
            begin
              require 'uri'
              require 'json'
              require 'ddtrace/monkey'
              require 'ddtrace/pin'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/contrib/elasticsearch/quantize'

              patch_elasticsearch_transport_client()

              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Elastic Search integration: #{e}")
            end
          end
          @patched
        end

        # rubocop:disable Metrics/MethodLength
        def patch_elasticsearch_transport_client
          # rubocop:disable Metrics/BlockLength
          ::Elasticsearch::Transport::Client.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Monkey.without_warnings do
              remove_method :initialize
            end

            def initialize(*args)
              service = Datadog.configuration[:elasticsearch][:service_name]
              pin = Datadog::Pin.new(service, app: 'elasticsearch', app_type: Datadog::Ext::AppTypes::DB)
              pin.onto(self)
              initialize_without_datadog(*args)
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
              pin.tracer.trace('elasticsearch.query') do |span|
                begin
                  span.service = pin.service
                  span.span_type = SPAN_TYPE

                  # load JSON for the following fields unless they're already strings
                  params = JSON.generate(params) if params && !params.is_a?(String)
                  body = JSON.generate(body) if body && !body.is_a?(String)

                  span.set_tag(METHOD, method)
                  span.set_tag(URL, url)
                  span.set_tag(PARAMS, params) if params
                  span.set_tag(BODY, body) if body

                  quantized_url = Datadog::Contrib::Elasticsearch::Quantize.format_url(url)
                  span.resource = "#{method} #{quantized_url}"
                rescue StandardError => e
                  Datadog::Tracer.log.error(e.message)
                ensure
                  # the call is still executed
                  response = perform_request_without_datadog(*args)
                  span.set_tag('http.status_code', response.status)
                end
              end
              response
            end
          end
        end

        # patched? tells wether patch has been successfully applied
        def patched?
          @patched
        end
      end
    end
  end
end
