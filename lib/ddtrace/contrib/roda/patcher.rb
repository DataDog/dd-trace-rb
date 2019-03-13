require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/roda/ext'

module Datadog
  module Contrib
    # Datadog Roda integration.
    module Roda
      # Patcher enables patching of 'net/http' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:roda)
        end

        # patch applies our patch if needed
        def patch
          do_once(:roda) do
            begin
              require 'uri'
              require 'ddtrace/pin'

              patch_roda
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply roda integration: #{e}")
            end
          end
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/BlockLength
        # rubocop:disable Metrics/AbcSize
        def patch_roda
          ::Roda::RodaPlugins::Base::InstanceMethods.class_eval do
            alias_method :call_without_datadog, :call
            remove_method :call

            def datadog_pin
              @datadog_pin ||= begin
                service = Datadog.configuration[:roda][:service_name]
                tracer = Datadog.configuration[:roda][:tracer]

                Datadog::Pin.new(service, app: Ext::APP, app_type: Datadog::Ext::AppTypes::WEB, tracer: tracer)
              end
            end

            def call(&block)
              pin = datadog_pin
              return call_without_datadog(&block) unless pin && pin.tracer

              pin.tracer.trace(Ext::SPAN_REQUEST) do |span|
                begin
                  req = ::Rack::Request.new(env)
                  request_method = req.request_method.to_s.upcase
                  path = req.path

                  parts = path.to_s.rpartition("/")
                  action = parts.last
                  controller = parts.first.sub(/\A\//, '').split("/").collect {|w| w.capitalize }.join("::")
                  operation = "#{controller}##{action}"

                  span.service = pin.service
                  span.span_type = Datadog::Ext::HTTP::TYPE

                  span.resource = request_method
                  # Using the method as a resource, as URL/path can trigger
                  # a possibly infinite number of resources.
                  span.set_tag(Ext::URL, path)
                  span.set_tag(Ext::METHOD, request_method)
                rescue StandardError => e
                  Datadog::Tracer.log.error("error preparing span for roda request: #{e}")
                ensure
                  response = call_without_datadog(&block)
                end

                response
              end
            end
          end
        end
      end
    end
  end
end
