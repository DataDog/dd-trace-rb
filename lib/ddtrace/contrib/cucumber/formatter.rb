require 'ddtrace/ext/app_types'
require 'ddtrace/ext/ci'
require 'ddtrace/ext/test'
require 'ddtrace/contrib/analytics'
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
          trace_options = {
            app: Ext::APP,
            resource: event.test_case.name,
            service: configuration[:service_name],
            span_type: Datadog::Ext::AppTypes::TEST,
            tags: tags.merge(Datadog.configuration.tags)
          }
          @current_feature_span = tracer.trace(configuration[:operation_name], trace_options)
          @current_feature_span.set_tag(Datadog::Ext::Test::TAG_FRAMEWORK, Ext::FRAMEWORK)
          @current_feature_span.set_tag(Datadog::Ext::Test::TAG_NAME, event.test_case.name)
          @current_feature_span.set_tag(Datadog::Ext::Test::TAG_SUITE, event.test_case.location.file)
          @current_feature_span.set_tag(Datadog::Ext::Test::TAG_TYPE, Ext::TEST_TYPE)
          @current_feature_span.set_tag(Datadog::Ext::Test::TAG_SPAN_KIND, Datadog::Ext::AppTypes::TEST)

          # Set analytics sample rate
          if Datadog::Contrib::Analytics.enabled?(configuration[:analytics_enabled])
            Datadog::Contrib::Analytics.set_sample_rate(@current_feature_span, configuration[:analytics_sample_rate])
          end

          # Measure service stats
          Contrib::Analytics.set_measured(@current_feature_span)
        end

        def on_test_case_finished(event)
          return if @current_feature_span.nil?
          @current_feature_span.status = 1 if event.result.failed?
          @current_feature_span.set_tag(Datadog::Ext::Test::TAG_STATUS, status_from_result(event.result))
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
          unless event.result.passed?
            @current_step_span.set_error event.result.exception
          end
          @current_step_span.set_tag(Datadog::Ext::Test::TAG_STATUS, status_from_result(event.result))
          @current_step_span.finish
        end

        private

        def status_from_result(result)
          if result.skipped?
            return Datadog::Ext::Test::Status::SKIP
          elsif result.ok?
            return Datadog::Ext::Test::Status::PASS
          end
          Datadog::Ext::Test::Status::FAIL
        end

        def configuration
          Datadog.configuration[:cucumber]
        end

        def tracer
          configuration[:tracer]
        end

        def tags
          @tags ||= Datadog::Ext::CI.tags(ENV)
        end
      end
    end
  end
end
