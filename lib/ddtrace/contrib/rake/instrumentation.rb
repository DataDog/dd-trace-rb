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
            return super unless enabled?

            tracer.trace(SPAN_NAME_INVOKE, span_options) do |span|
              super
              annotate_invoke!(span, args)
            end
            tracer.shutdown! if tracer.active_span.nil? && ::Rake.application.top_level_tasks.include?(name)
          end

          def execute(args = nil)
            return super unless enabled?

            tracer.trace(SPAN_NAME_EXECUTE, span_options) do |span|
              super
              annotate_execute!(span, args)
            end
            tracer.shutdown! if tracer.active_span.nil? && ::Rake.application.top_level_tasks.include?(name)
          end

          private

          def annotate_invoke!(span, args)
            span.resource = name
            span.set_tag('rake.task.arg_names', arg_names)
            span.set_tag('rake.invoke.args', quantize_args(args)) unless args.nil?
          rescue StandardError => e
            Datadog::Tracer.log.debug("Error while tracing Rake invoke: #{e.message}")
          end

          def annotate_execute!(span, args)
            span.resource = name
            span.set_tag('rake.execute.args', quantize_args(args.to_hash)) unless args.nil?
          rescue StandardError => e
            Datadog::Tracer.log.debug("Error while tracing Rake execute: #{e.message}")
          end

          def quantize_args(args)
            quantize_options = configuration[:quantize][:args]
            Datadog::Quantization::Hash.format(args, quantize_options)
          end

          def enabled?
            configuration[:enabled] == true
          end

          def tracer
            configuration[:tracer]
          end

          def span_options
            { service: configuration[:service_name] }
          end

          def configuration
            Datadog.configuration[:rake]
          end
        end
      end
    end
  end
end
