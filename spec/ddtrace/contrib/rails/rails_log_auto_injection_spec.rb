require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails Log Auto Injection' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) do
    {
      '/lograge' => 'lograge_test#index',
      '/tagged_logging' => 'tagged_logging_test#index'
    }
  end

  let(:controllers) do
    [
      tagged_logging_controller,
      lograge_controller
    ]
  end

  let(:tagged_logging_controller) do
    stub_const('TaggedLoggingTestController', Class.new(ActionController::Base) do
      def index
        Rails.logger.info('MINASWAN')
        render inline: '<html> <head> </head> <body> <div> Hello from index </div> </body> </html>'
      end
    end)
  end

  let(:lograge_controller) do
    stub_const('LogrageTestController', Class.new(ActionController::Base) do
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

  context 'with Log_Injection Enabled' do
    # defined in rails support apps
    let(:logs) { log_output.string }

    if Rails.version >= '3.2'
      context 'with Tagged Logging' do
        subject(:response) { get '/tagged_logging' }

        before do
          allow(ENV).to receive(:[]).with('USE_TAGGED_LOGGING').and_return(true)
        end

        context 'with Tagged logging setup and no tags' do
          it 'injects trace_id into logs' do
            is_expected.to be_ok

            expect(logs).to include(spans[0].trace_id.to_s)
            expect(logs).to include('MINASWAN')
          end
        end

        context 'with tagged logging setup and existing log_tags' do
          before do
            allow(ENV).to receive(:[]).with('LOG_TAGS').and_return(%w[some_info some_other_info])
          end

          it 'injects trace_id into logs and preserve existing log tags' do
            is_expected.to be_ok

            expect(logs).to include(spans[0].trace_id.to_s)
            expect(logs).to include('MINASWAN')
            expect(logs).to include('some_info')
            expect(logs).to include('some_other_info')
          end
        end
      end
    end

    if Rails.version >= '4.0'
      # for log_injection testing
      require 'lograge'
      context 'with Lograge' do
        subject(:response) { get '/lograge' }

        before do
          allow(ENV).to receive(:[]).with('USE_LOGRAGE').and_return(true)
        end

        context 'with lograge enabled' do
          context 'with Lograge setup and no custom_options' do
            it 'injects trace_id into logs' do
              is_expected.to be_ok

              expect(logs).to include(spans[0].trace_id.to_s)
              expect(logs).to include('MINASWAN')
            end
          end

          context 'with Lograge and existing custom_options as a hash' do
            before do
              allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
                'some_hash_info' => 'test_hash_value',
                'some_other_hash_info' => 'other_test_hash_value'
              )
            end

            it 'injects trace_id into logs and preserve existing hash' do
              is_expected.to be_ok

              expect(logs).to include(spans[0].trace_id.to_s)
              expect(logs).to include('MINASWAN')
              expect(logs).to include('some_hash_info')
              expect(logs).to include('some_other_hash_info')
              expect(logs).to include('test_hash_value')
              expect(logs).to include('other_test_hash_value')
            end
          end

          context 'with Lograge and existing custom_options as a lambda' do
            before do
              allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
                lambda do |_event|
                  {
                    'some_lambda_info' => 'test_lambda_value',
                    'some_other_lambda_info' => 'other_test_lambda_value'
                  }
                end
              )
            end

            it 'injects trace_id into logs and preserve existing lambda' do
              is_expected.to be_ok

              expect(logs).to include(spans[0].trace_id.to_s)
              expect(logs).to include('MINASWAN')
              expect(logs).to include('some_lambda_info')
              expect(logs).to include('some_other_lambda_info')
              expect(logs).to include('test_lambda_value')
              expect(logs).to include('other_test_lambda_value')
            end
          end
        end

        context 'with lograge disabled' do
          before do
            allow(ENV).to receive(:[]).with('LOGRAGE_DISABLED').and_return(true)
          end

          it 'does not inject trace_id into logs' do
            is_expected.to be_ok

            expect(logs).not_to include(spans[0].trace_id.to_s)
            expect(logs).to include('MINASWAN')
          end
        end
      end
    end
  end
end
