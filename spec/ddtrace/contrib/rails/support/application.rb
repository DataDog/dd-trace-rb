require 'ddtrace/contrib/rails/support/base'

RSpec.shared_context 'Rails test application' do
  include_context 'Rails base application'

  let(:app) do
    rails_test_application.instance
  end

  before(:each) do
    # Reinitializing Rails applications generates a lot of warnings.
    without_warnings do
      # Initialize the application and stub Rails with the test app
      rails_test_application.test_initialize!
    end
  end

  if Rails.version < '4.0'
    around(:each) do |example|
      without_warnings do
        example.run
      end
    end
  end

  if Rails.version >= '5.0'
    let(:rails_test_application) do
      stub_const('Rails5::Application', Class.new(rails_base_application))
    end
  elsif Rails.version >= '4.0'
    let(:rails_test_application) do
      stub_const('Rails4::Application', Class.new(rails_base_application))
    end
  elsif Rails.version >= '3.0'
    let(:rails_test_application) do
      stub_const('Rails3::Application', rails_base_application)
    end
  else
    logger.error 'A Rails app for this version is not found!'
  end
end
