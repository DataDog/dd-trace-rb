module TestHelpers
  module_function

  # Integration tests are normally expensive (time-wise or resource-wise).
  # They run in CI by default.
  def run_integration_tests?
    ENV['TEST_DATADOG_INTEGRATION']
  end

  module RSpec
    # RSpec extension to allow for declaring integration tests
    # using example group parameters:
    #
    # ```ruby
    # describe 'end-to-end foo test', :integration do
    # ...
    # end
    # ```
    module Integration
      def self.included(base)
        base.class_exec do
          before do
            unless run_integration_tests?
              skip('Integration tests can be enabled by setting the environment variable `TEST_DATADOG_INTEGRATION=1`')
            end
          end
        end
      end
    end
  end
end
