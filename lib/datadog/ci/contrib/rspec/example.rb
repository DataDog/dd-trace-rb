require 'datadog/ci/test'

require 'datadog/ci/ext/app_types'
require 'datadog/ci/ext/environment'
require 'datadog/ci/ext/test'
require 'datadog/ci/contrib/rspec/ext'

module Datadog
  module CI
    module Contrib
      module RSpec
        # Instrument RSpec::Core::Example
        module Example
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # Instance methods for configuration
          module InstanceMethods
            def run(example_group_instance, reporter)
              return super unless configuration[:enabled]

              test_name = full_description.strip
              if metadata[:description].empty?
                # for unnamed it blocks this appends something like "example at ./spec/some_spec.rb:10"
                test_name += " #{description}"
              end

              CI::Test.trace(
                tracer,
                configuration[:operation_name],
                {
                  span_options: {
                    app: Ext::APP,
                    resource: test_name,
                    service: configuration[:service_name]
                  },
                  framework: Ext::FRAMEWORK,
                  test_name: test_name,
                  test_suite: file_path,
                  test_type: Ext::TEST_TYPE
                }
              ) do |span|
                result = super

                case execution_result.status
                when :passed
                  CI::Test.passed!(span)
                when :failed
                  CI::Test.failed!(span, execution_result.exception)
                else
                  CI::Test.skipped!(span, execution_result.exception) if execution_result.example_skipped?
                end

                result
              end
            end

            private

            def configuration
              Datadog.configuration[:rspec]
            end

            def tracer
              configuration[:tracer]
            end
          end
        end
      end
    end
  end
end
