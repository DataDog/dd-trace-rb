require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/cucumber/ext'

module Datadog
  module Contrib
    module Cucumber
      # Defines collection of instrumented Cucumber events
      class Formatter
        attr_reader :config
        private :config

        attr_reader :current_feature_span, :current_step_span
        private :current_feature_span, :current_step_span

        def initialize(config)
          @config = config

          bind_events(config)
        end

        def bind_events(config)
          config.on_event :test_case_started, &method(:on_test_case_started)
          config.on_event :test_case_finished, &method(:on_test_case_finished)
          config.on_event :test_step_started, &method(:on_test_step_started)
          config.on_event :test_step_finished, &method(:on_test_step_finished)
        end

        def on_test_case_started(event)
          pin = Datadog::Pin.get_from(::Cucumber)
          trace_options = {
            service: pin.service_name,
            resource: event.test_case.name,
            span_type: Datadog::Ext::AppTypes::TEST,
            tags: pin.tags
          }
          @current_feature_span = pin.tracer.trace(Datadog::Ext::AppTypes::TEST, trace_options)
        end

        def on_test_case_finished(event)
          return if @current_feature_span.nil?
          @current_feature_span.status = 1 if event.result.failed?
          @current_feature_span.finish
        end

        def on_test_step_started(event)
          pin = Datadog::Pin.get_from(::Cucumber)
          trace_options = {
            resource: event.test_step.to_s,
            span_type: Datadog::Contrib::Cucumber::Ext::STEP_SPAN_TYPE
          }
          @current_step_span = pin.tracer.trace('step', trace_options)
        end

        def on_test_step_finished(event)
          return if @current_step_span.nil?
          unless event.result.passed?
            @current_step_span.set_error event.result.exception
          end
          @current_step_span.finish
        end
      end
    end
  end
end
