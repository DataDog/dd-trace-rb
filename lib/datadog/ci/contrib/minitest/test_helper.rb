# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module CI
    module Contrib
      module Minitest
        # Instrument Minitest::Test
        module TestHelper
          def before_setup
            super
            return unless configuration[:enabled]

            test_name = "#{class_name}##{name}"

            path, = method(name).source_location
            test_suite = Pathname.new(path).relative_path_from(Pathname.pwd).to_s

            span = CI::Test.trace(
              configuration[:operation_name],
              {
                span_options: {
                  resource: test_name,
                  service: configuration[:service_name],
                },
                framework: Ext::FRAMEWORK,
                framework_version: CI::Contrib::Minitest::Integration.version.to_s,
                test_name: test_name,
                test_suite: test_suite,
                test_type: Ext::TEST_TYPE,
              },
            )

            Thread.current[:_datadog_test_span] = span
          end

          def after_teardown
            span = Thread.current[:_datadog_test_span]
            return super unless span

            Thread.current[:_datadog_test_span] = nil

            case result_code
            when '.'
              CI::Test.passed!(span)
            when 'E', 'F'
              CI::Test.failed!(span, failure)
            when 'S'
              CI::Test.skipped!(span)
              span.set_tag(CI::Ext::Test::TAG_SKIP_REASON, failure.message)
            end

            span.finish

            super
          end

          private

          def configuration
            ::Datadog.configuration.ci[:minitest]
          end
        end
      end
    end
  end
end
