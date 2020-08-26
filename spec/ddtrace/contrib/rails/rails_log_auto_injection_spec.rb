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

      context 'with tagged logging setupu and existing log_tags' do
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
    end
  end
end
