module TestHelpers
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
          skip_unless_integration_testing_enabled

          include_context 'non-development execution environment'
        end
      end
    end
  end
end
