# TODO move to another file, with basic controller tests.
# TODO this doesn't need a file anymore, as I'm mocking environment variables

require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails application' do
  include Rack::Test::Methods
  include_context 'Rails test application'
  include_context 'Tracer'

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISABLE_DATADOG_RAILS").and_return("1")
  end

  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    Datadog.configuration[:rails][:tracer] = tracer
  end

  after do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  let(:routes) { { '/' => 'test#index' } }

  let(:controllers) { [controller] }

  let(:controller) do
    stub_const('TestController', Class.new(ActionController::Base) do
      def index
        head :ok
      end
    end)
  end

  it 'does not instrument' do
    # make the request and assert the proper span
    get '/'
    expect(last_response).to be_ok
    expect(spans).to be_empty
  end

  it 'manual instrumentation should still work' do
    tracer.trace('a-test') {}
    expect(spans).to have(1).item
  end
end
