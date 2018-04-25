module Datadog
  module Contrib
    module Rake
      # Instrumentation for Rake tasks
      module Instrumentation
        SPAN_NAME_INVOKE = 'rake.invoke'.freeze
        SPAN_NAME_EXECUTE = 'rake.execute'.freeze

        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        # Instance methods for Rake instrumentation
        module InstanceMethods
          def invoke(*args)
            if enabled?
              tracer.trace(SPAN_NAME_INVOKE) do |span|
                super
                annotate!(span)
                # TODO: Add quantization
                span.set_tag('rake.args', args)
              end
            else
              super
            end
          end

          def execute(args = nil)
            if enabled?
              tracer.trace(SPAN_NAME_EXECUTE) do |span|
                super
                annotate!(span)
                # TODO: Add quantization
                span.set_tag('rake.args', args.to_hash) unless args.nil?
              end
            else
              super
            end
          end

          private

          def annotate!(span)
            span.resource = name
            span.set_tag('rake.arg_names', arg_names)
          end

          def enabled?
            configuration[:enabled] == true
          end

          def tracer
            configuration[:tracer]
          end

          def configuration
            Datadog.configuration[:rake]
          end
        end
      end
    end
  end
end
