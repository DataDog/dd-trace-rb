require 'datadog/ci/test'
require 'datadog/ci/ext/app_types'
require 'datadog/ci/ext/environment'
require 'datadog/ci/ext/test'
require 'datadog/ci/contrib/cucumber/ext'

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Defines collection of instrumented Cucumber events
        class Formatter
          attr_reader :config, :current_feature_span, :current_step_span
          private :config
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
            @current_feature_span = CI::Test.trace(
              tracer,
              configuration[:operation_name],
              {
                span_options: {
                  app: Ext::APP,
                  resource: event.test_case.name,
                  service: configuration[:service_name]
                },
                framework: Ext::FRAMEWORK,
                test_name: event.test_case.name,
                test_suite: event.test_case.location.file,
                test_type: Ext::TEST_TYPE
              }
            )
          end

          def on_test_case_finished(event)
            return if @current_feature_span.nil?

            if event.result.skipped?
              CI::Test.skipped!(@current_feature_span)
            elsif event.result.ok?
              CI::Test.passed!(@current_feature_span)
            elsif event.result.failed?
              CI::Test.failed!(@current_feature_span)
            end

            @current_feature_span.finish
          end

          def on_test_step_started(event)
            trace_options = {
              resource: event.test_step.to_s,
              span_type: Ext::STEP_SPAN_TYPE
            }
            @current_step_span = tracer.trace(Ext::STEP_SPAN_TYPE, trace_options)
          end

          def on_test_step_finished(event)
            return if @current_step_span.nil?

            if event.result.skipped?
              CI::Test.skipped!(@current_step_span, event.result.exception)
            elsif event.result.ok?
              CI::Test.passed!(@current_step_span)
            elsif event.result.failed?
              CI::Test.failed!(@current_step_span, event.result.exception)
            end

            @current_step_span.finish
          end

          private

          def configuration
            Datadog.configuration[:cucumber]
          end

          def tracer
            configuration[:tracer]
          end
        end
      end
    end
  end
end
