require 'datadog/tracing/contrib/rails/support/base'
require 'spec/datadog/tracing/contrib/rails/support/deprecation'

RSpec.shared_context 'Rails test application' do
  include_context 'Rails base application'

  before do
    reset_rails_configuration!
    raise_on_rails_deprecation!
  end

  after do
    reset_rails_configuration!

    # Reset references stored in the Rails class
    Rails.application = nil
    Rails.logger = nil

    if Rails::VERSION::MAJOR >= 4
      Rails.app_class = nil
      Rails.cache = nil
    end

    without_warnings { Datadog.configuration.reset! }
    Datadog.configuration.tracing[:rails].reset_options!
    Datadog.configuration.tracing[:rack].reset_options!
    Datadog.configuration.tracing[:redis].reset_options!
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
    clear_traces!
  end

  if Rails.version < '4.0'
    around do |example|
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
  elsif Rails.version >= '3.2'
    let(:rails_test_application) do
      stub_const('Rails3::Application', rails_base_application)
    end
  else
    logger.error 'A Rails app for this version is not found!'
  end

  let(:tracer_options) { {} }

  let(:app_name) { Datadog::Tracing::Contrib::Rails::Utils.app_name }

  def adapter_name
    Datadog::Tracing::Contrib::ActiveRecord::Utils.adapter_name
  end

  def adapter_host
    Datadog::Tracing::Contrib::ActiveRecord::Utils.adapter_host
  end

  def adapter_port
    Datadog::Tracing::Contrib::ActiveRecord::Utils.adapter_port
  end

  def database_name
    Datadog::Tracing::Contrib::ActiveRecord::Utils.database_name
  end
end
