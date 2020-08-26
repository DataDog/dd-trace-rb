require 'ddtrace/contrib/rails/rails_helper'
require_relative 'support/rails_log_auto_injection_helper'

RSpec.describe 'Rails Rack Rum Injection middleware' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) do
    {
      '/' => 'log_test#index'
    }
  end

  let(:controllers) do
    [
      controller
    ]
  end

  let(:controller) do
    stub_const('LogTestController', Class.new(ActionController::Base) do
      def index
        logger.info('MINASWAN')
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
    RailsLogAutoInjectionHelper.wipe_logs
  end

  context 'with Log_Injection Enabled' do
    subject(:response) { get '/' }

    context 'with Tagged Logging' do
      before do
        allow(ENV).to receive(:[]).with('USE_TAGGED_LOGGING').and_return('true')
      end

      context 'with Tagged logging setup and no tags' do
        it 'should inject trace_id into logs' do
          is_expected.to be_ok
          logs = RailsLogAutoInjectionHelper.read_logs
          expect(logs).to include(spans[0].trace_id.to_s)
          expect(logs).to include('MINASWAN')
        end
      end

      context 'with tagged logging setup and existing log_tags' do
        before do
          allow(ENV).to receive(:[]).with('LOG_TAGS').and_return(%w[some_info some_other_info])
        end

        it 'should inject trace_id into logs and preserve existing log tags' do
          is_expected.to be_ok
          logs = RailsLogAutoInjectionHelper.read_logs
          expect(logs).to include(spans[0].trace_id.to_s)
          expect(logs).to include('MINASWAN')
          expect(logs).to include('some_info')
          expect(logs).to include('some_other_info')
        end
      end

      context 'with Lograge' do
        before do
          allow(ENV).to receive(:[]).with('USE_LOGRAGE').and_return('true')
        end

        context 'with Lograge setup and no custom_options' do
          it 'should inject trace_id into logs' do
            is_expected.to be_ok
            logs = RailsLogAutoInjectionHelper.read_logs
            expect(logs).to include(spans[0].trace_id.to_s)
            expect(logs).to include('MINASWAN')
          end
        end

        context 'with Lograge and existing custom_options as a hash' do
          before do
            allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
              'some_hash_info' => 'test info',
              'some_other_hash_info' => 'yes'
            )
          end

          it 'should inject trace_id into logs and preserve existing hash' do
            is_expected.to be_ok
            logs = RailsLogAutoInjectionHelper.read_logs
            expect(logs).to include(spans[0].trace_id.to_s)
            expect(logs).to include('MINASWAN')
            expect(logs).to include('some_hash_info')
            expect(logs).to include('some_other_hash_info')
          end
        end

        context 'with Lograge and existing custom_options as a lambda' do
          before do
            allow(ENV).to receive(:[]).with('LOGRAGE_CUSTOM_OPTIONS').and_return(
              lambda do |_event|
                return { 'some_lambda_info' => 'test info', 'some_other_lambda_info' => 'yes' }
              end
            )
          end

          it 'should inject trace_id into logs and preserve existing lambda' do
            is_expected.to be_ok
            logs = RailsLogAutoInjectionHelper.read_logs
            expect(logs).to include(spans[0].trace_id.to_s)
            expect(logs).to include('MINASWAN')
            expect(logs).to include('some_lambda_info')
            expect(logs).to include('some_other_lambda_info')
          end
        end
      end
    end
  end
end
