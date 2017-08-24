module Datadog
  module Contrib
    module Aws
      # A Seahorse::Client::Plugin that enables instrumentation for all AWS services
      class Instrumentation < Seahorse::Client::Plugin
        def add_handlers(handlers, _)
          handlers.add(Handler, step: :validate)
        end
      end

      # Generates Spans for all interactions with AWS
      class Handler < Seahorse::Client::Handler
        def call(context)
          pin = Datadog::Pin.get_from(::Aws)

          return @handler.call(context) unless pin && pin.enabled?

          pin.tracer.trace(RESOURCE) do |span|
            result = @handler.call(context)
            annotate!(span, pin, ParsedContext.new(context))
            result
          end
        end

        private

        def annotate!(span, pin, context)
          span.service = pin.service
          span.span_type = pin.app_type
          span.name = context.safely(:resource)
          span.resource = RESOURCE
          span.set_tag('aws.agent', AGENT)
          span.set_tag('aws.operation', context.safely(:operation))
          span.set_tag('aws.region', context.safely(:region))
          span.set_tag('path', context.safely(:path))
          span.set_tag('host', context.safely(:host))
          span.set_tag(Ext::HTTP::METHOD, context.safely(:http_method))
          span.set_tag(Ext::HTTP::STATUS_CODE, context.safely(:status_code))
        end
      end
    end
  end
end
