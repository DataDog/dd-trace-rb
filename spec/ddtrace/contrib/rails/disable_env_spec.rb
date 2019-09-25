# This scenario requires Rails to *not* have been patched yet.
# This file cannot be run after any tests that patch Rails, but
# it can be the first Rails test in a process.

require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails disabled' do
  before(:all) do
    expect(Datadog::Contrib::Rails::Patcher.patched?).to(
      be_falsey, <<MESSAGE)
      Rails has already been patched.
      This suite tests the behaviour of dd-trace-rb when patching is disabled for Rails.
      Please run this suite before Rails is patched.
MESSAGE
  end

  include Rack::Test::Methods
  include_context 'Rails test application'

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('DISABLE_DATADOG_RAILS').and_return('1')
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
