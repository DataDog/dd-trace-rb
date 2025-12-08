require_relative 'controllers'
require_relative 'models'
require_relative 'log_configuration'

require_relative 'deprecation'

RSpec.shared_context 'Rails base application' do
  include_context 'Rails controllers'
  include_context 'Rails models'
  include_context 'Rails log configuration'

  before do
    raise_on_rails_deprecation!
  end

  after do
    # NOTE: We forsibly close connection pool to avoid leaking connection between
    #       test cases.
    #       This call is safe to be used on already closed connection pool.
    application_record.connection.disconnect! if application_record&.connected?

    # Reset references stored in the Rails class
    Rails.application = nil
    Rails.logger = nil

    # Uncommnt this when Rails 3 removed
    # Rails.app_class = nil
    # Rails.cache = nil
  end

  let(:rails_base_application) do
    raise 'Must be implemented by each version of Rails test app.'
  end

  let(:rails_test_application) do
    stub_const('RailsTest::Application', rails_base_application)
  end

  let(:app) do
    # Reinitializing Rails applications generates a lot of warnings.
    without_warnings do
      # Initialize the application and stub Rails with the test app
      rails_test_application.test_initialize!
    end

    # Clear out any spans generated during initialization
    clear_traces!

    # Clear out log entries generated during initialization
    log_output.reopen

    rails_test_application.instance
  end

  let(:rails_middleware) { [] }

  let(:initialize_block) do
    middleware = rails_middleware
    log_configuration = ::Datadog::Tracing::Contrib::Rails::Test::LogConfiguration.new(self)

    proc do
      log_configuration.setup(config)
      middleware.each { |m| config.middleware.use m }
    end
  end

  around do |example|
    # Workaround for a `pg` gem bug on Mac, when the process forks: https://github.com/ged/ruby-pg/issues/538
    ClimateControl.modify('PGGSSENCMODE' => 'disable') do
      example.run
    end
  end
end
