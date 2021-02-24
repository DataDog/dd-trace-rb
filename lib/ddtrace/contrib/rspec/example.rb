module Datadog
  module Contrib
    module RSpec
      # Instrument RSpec::Core::Example
      module Example
        def self.included(base)
          base.send(:prepend, InstanceMethods)
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

            trace_options = {
              app: Ext::APP,
              resource: test_name,
              service: configuration[:service_name],
              span_type: Datadog::Ext::AppTypes::TEST,
              tags: tags.merge(Datadog.configuration.tags)
            }

            tracer.trace(configuration[:operation_name], trace_options) do |span|
              span.set_tag(Datadog::Ext::Test::TAG_FRAMEWORK, Ext::FRAMEWORK)
              span.set_tag(Datadog::Ext::Test::TAG_NAME, test_name)
              span.set_tag(Datadog::Ext::Test::TAG_SUITE, file_path)
              span.set_tag(Datadog::Ext::Test::TAG_TYPE, Ext::TEST_TYPE)
              span.set_tag(Datadog::Ext::Test::TAG_SPAN_KIND, Datadog::Ext::AppTypes::TEST)

              # Measure service stats
              Contrib::Analytics.set_measured(span)

              result = super

              case execution_result.status
              when :passed
                span.set_tag(Datadog::Ext::Test::TAG_STATUS, Datadog::Ext::Test::Status::PASS)
              when :failed
                span.status = 1
                span.set_tag(Datadog::Ext::Test::TAG_STATUS, Datadog::Ext::Test::Status::FAIL)
                span.set_error(execution_result.exception)
              else
                if execution_result.example_skipped?
                  span.set_tag(Datadog::Ext::Test::TAG_STATUS, Datadog::Ext::Test::Status::SKIP)
                end
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

          def tags
            @tags ||= Datadog::Ext::CI.tags(ENV)
          end
        end
      end
    end
  end
end
