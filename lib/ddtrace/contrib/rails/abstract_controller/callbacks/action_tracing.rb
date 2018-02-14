module Datadog
  module Contrib
    module Rails
      module AbstractController
        module Callbacks
          # Patches process_action for tracing
          module ActionTracing
            def process_action(*args)
              tracer = Datadog.configuration[:rails][:tracer]
              tracer.trace('rails.action_controller.process_action') do |span|
                span.resource = "#{self.class}##{args.first}"
                span.service = Datadog.configuration[:rails][:controller_service]
                span.span_type = Ext::HTTP::TYPE

                super
              end
            end
          end
        end
      end
    end
  end
end
