# This scenario requires Rails to *not* have been patched yet.
# This file cannot be run after any tests that patch Rails, but
# it can be the first Rails test in a process.

require 'datadog/tracing/contrib/rails/rails_helper'

RSpec.describe 'Rails disabled', execute_in_fork: Rails.version.to_i >= 8 do
  before(:all) do
    expect(Datadog::Tracing::Contrib::Rails::Patcher.patched?).to(
      be_falsey, <<MESSAGE)
      Rails has already been patched.
      This suite tests the behaviour of dd-trace-rb when patching is disabled for Rails.
      Please run this suite before Rails is patched.
MESSAGE
  end

  include Rack::Test::Methods
  include_context 'Rails test application'

  shared_examples 'rails patching disabled' do
    let(:routes) { {'/' => 'test#index'} }

    let(:controllers) { [controller] }

    let(:controller) do
      stub_const(
        'TestController',
        Class.new(ActionController::Base) do
          def index
            head :ok
          end
        end
      )
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

  context 'when DD_DISABLE_DATADOG_RAILS is set' do
    with_env 'DD_DISABLE_DATADOG_RAILS' => '1'

    it_behaves_like 'rails patching disabled'
  end

  context 'when DISABLE_DATADOG_RAILS is set' do
    with_env 'DISABLE_DATADOG_RAILS' => '1'

    it_behaves_like 'rails patching disabled'
  end
end
