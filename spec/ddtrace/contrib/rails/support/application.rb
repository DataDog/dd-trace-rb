require 'ddtrace/contrib/rails/support/base'

RSpec.shared_context 'Rails test application' do
  include_context 'Rails base application'

  before do
    Datadog.configuration[:rails].reset_options!

    reset_rails_configuration!
  end

  after do
    # Reset references stored in the Rails class
    Rails.application = nil
    Rails.logger = nil

    if Rails::VERSION::MAJOR >= 4
      Rails.app_class = nil
      Rails.cache = nil
    end
  end

  let(:app) do
    initialize_app!
    rails_test_application.instance
  end

  def initialize_app!
    # Reinitializing Rails applications generates a lot of warnings.
    without_warnings do
      # Initialize the application and stub Rails with the test app
      rails_test_application.test_initialize!
    end

    # Clear out any spans generated during initialization
    clear_spans!
  end

  if Rails.version < '4.0'
    around(:each) do |example|
      without_warnings do
        example.run
      end
    end
  end

  if Rails.version >= '6.0'
    let(:rails_test_application) do
      stub_const('Rails6::Application', Class.new(rails_base_application))
    end
  elsif Rails.version >= '5.0'
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

  let(:tracer_options) { {} }

  let(:app_name) { Datadog::Contrib::Rails::Utils.app_name }

  def adapter_name
    Datadog::Contrib::ActiveRecord::Utils.adapter_name
  end

  def adapter_host
    Datadog::Contrib::ActiveRecord::Utils.adapter_host
  end

  def adapter_port
    Datadog::Contrib::ActiveRecord::Utils.adapter_port
  end

  def database_name
    Datadog::Contrib::ActiveRecord::Utils.database_name
  end
end
