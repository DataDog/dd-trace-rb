require 'ddtrace/contrib/roda/ext'
require 'ddtrace/contrib/analytics'

module Datadog
	module Contrib
		module Roda
			module Instrumentation

		    def datadog_pin
          @datadog_pin ||= begin
            service = Datadog.configuration[:roda][:service_name]
            tracer = Datadog.configuration[:roda][:tracer]

            Datadog::Pin.new(service, app: Ext::APP, app_type: Datadog::Ext::AppTypes::WEB, tracer: tracer)
          end
        end
        
        def call(*args)
          pin = datadog_pin
          return super unless pin && pin.tracer

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
              span.set_tag(Datadog::Ext::HTTP::URL, path)
              span.set_tag(Datadog::Ext::HTTP::METHOD, request_method)
            
            	# Add analytics tag to the span
           		Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate]) if Contrib::Analytics.enabled?(Datadog.configuration[:roda][:analytics_enabled])

            rescue StandardError => e
              Datadog::Tracer.log.error("error preparing span for roda request: #{e}")
            ensure
              response = super
            end

            # response comes back as [404, {"Content-Type"=>"text/html", "Content-Length"=>"0"}, []]
            span.set_error(1) if response[0].to_s.start_with?("5")
            response	
          end
        end
			end
		end
	end
end