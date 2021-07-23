require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails Log Auto Injection' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) do
    {
      '/semantic_logger' => 'semantic_logger_test#index'
    }
  end

  let(:controllers) do
    [
      semantic_logger_controller
    ]
  end

  let(:semantic_logger_controller) do
    stub_const('SemanticLoggerTestController', Class.new(ActionController::Base) do
      def index
        Rails.logger.info('MINASWAN')
        render inline: '<html> <head> </head> <body> <div> Hello from index </div> </body> </html>'
      end
    end)
  end

  before do
    Datadog.configuration[:rails].reset_options!
    Datadog.configure do |c|
      c.use :rails, log_injection: true
    end

    allow(ENV).to receive(:[]).and_call_original
  end

  after do
    Datadog.configuration[:rails].reset_options!
  end

  context 'with Log_Injection Enabled', if: Rails.version >= '4.0' do
    # defined in rails support apps
    let(:logs) { log_output.string }
    let(:test_env) { 'test-env' }
    let(:test_version) { 'test-version' }
    let(:test_service) { 'test-service' }

    context 'with Semantic Logger' do
      # for logsog_injection testing
      require 'rails_semantic_logger'
      subject(:response) { get '/semantic_logger' }

      before do
        Datadog.configure do |c|
          c.use :rails, log_injection: true
          c.env = test_env
          c.version = test_version
          c.service = test_service
        end

        allow(ENV).to receive(:[]).with('USE_SEMANTIC_LOGGER').and_return(true)
      end

      after do
        SemanticLogger.close
      end

      context 'with semantic logger enabled' do
        context 'with semantic logger setup and no log_tags' do
          it 'injects trace_id into logs' do
            is_expected.to be_ok
            # force flush
            SemanticLogger.flush

            expect(logs).to include(spans[0].trace_id.to_s)
            expect(logs).to include(spans[0].span_id.to_s)
            expect(logs).to include(test_env)
            expect(logs).to include(test_version)
            expect(logs).to include(test_service)
            expect(logs).to include('MINASWAN')
          end
        end

        context 'with semantic logger setup and existing log_tags' do
          before do
            allow(ENV).to receive(:[]).with('LOG_TAGS').and_return({ some_tag: 'some_value' })
          end

          it 'injects trace correlation context into logs and preserve existing log tags' do
            is_expected.to be_ok
            # force flush
            SemanticLogger.flush

            expect(logs).to include(spans[0].trace_id.to_s)
            expect(logs).to include(spans[0].span_id.to_s)
            expect(logs).to include(test_env)
            expect(logs).to include(test_version)
            expect(logs).to include(test_service)
            expect(logs).to include('MINASWAN')
            expect(logs).to include('some_tag')
            expect(logs).to include('some_value')
          end
        end
      end
    end
  end
end
