# typed: false
require 'ddtrace/contrib/utils/quantization/hash'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/rake/ext'

module Datadog
  module Contrib
    module Rake
      # Instrumentation for Rake tasks
      module Instrumentation
        def self.included(base)
          base.prepend(InstanceMethods)
        end

        # Instance methods for Rake instrumentation
        module InstanceMethods
          def invoke(*args)
            return super unless enabled?

            Datadog::Tracing.trace(Ext::SPAN_INVOKE, **span_options) do |span|
              annotate_invoke!(span, args)
              super
            end
          ensure
            shutdown_tracer!
          end

          def execute(args = nil)
            return super unless enabled?

            Datadog::Tracing.trace(Ext::SPAN_EXECUTE, **span_options) do |span|
              annotate_execute!(span, args)
              super
            end
          ensure
            shutdown_tracer!
          end

          private

          def shutdown_tracer!
            if Datadog::Tracing.active_span.nil? && ::Rake.application.top_level_tasks.include?(name)
              Datadog::Tracing.shutdown!
            end
          end

          def annotate_invoke!(span, args)
            span.resource = name
            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_INVOKE)
            span.set_tag(Ext::TAG_TASK_ARG_NAMES, arg_names)
            span.set_tag(Ext::TAG_INVOKE_ARGS, quantize_args(args)) unless args.nil?
          rescue StandardError => e
            Datadog.logger.debug("Error while tracing Rake invoke: #{e.message}")
          end

          def annotate_execute!(span, args)
            span.resource = name
            span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_EXECUTE)
            span.set_tag(Ext::TAG_EXECUTE_ARGS, quantize_args(args.to_hash)) unless args.nil?
          rescue StandardError => e
            Datadog.logger.debug("Error while tracing Rake execute: #{e.message}")
          end

          def quantize_args(args)
            quantize_options = configuration[:quantize][:args]
            Contrib::Utils::Quantization::Hash.format(args, quantize_options)
          end

          def enabled?
            configuration[:enabled] == true
          end

          def span_options
            { service: configuration[:service_name] }
          end

          def configuration
            Datadog::Tracing.configuration[:rake]
          end
        end
      end
    end
  end
end
