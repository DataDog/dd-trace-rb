require 'ddtrace/contrib/aws/ext'

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

          pin.tracer.trace(Ext::SPAN_COMMAND) do |span|
            result = @handler.call(context)
            annotate!(span, pin, ParsedContext.new(context))
            result
          end
        end

        private

        def annotate!(span, pin, context)
          span.service = pin.service
          span.span_type = pin.app_type
          span.name = Ext::SPAN_COMMAND
          span.resource = context.safely(:resource)
          span.set_tag(Ext::TAG_AGENT, Ext::TAG_DEFAULT_AGENT)
          span.set_tag(Ext::TAG_OPERATION, context.safely(:operation))
          span.set_tag(Ext::TAG_REGION, context.safely(:region))
          span.set_tag(Ext::TAG_PATH, context.safely(:path))
          span.set_tag(Ext::TAG_HOST, context.safely(:host))
          span.set_tag(Datadog::Ext::HTTP::METHOD, context.safely(:http_method))
          span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, context.safely(:status_code))
        end
      end
    end
  end
end
