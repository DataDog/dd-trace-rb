require 'datadog/tracing/contrib/support/spec_helper'
require 'spec/datadog/tracing/contrib/rails/support/deprecation'

require 'ddtrace'

require 'datadog/tracing/contrib/rails/rails_helper'

require 'spec/support/thread_helpers'

begin
  require 'action_cable'
rescue LoadError
  puts 'ActionCable not supported in Rails < 5.0'
end

require 'websocket/driver'

RSpec.describe 'ActionCable Rack override' do
  before { skip('ActionCable not supported') unless Datadog::Tracing::Contrib::ActionCable::Integration.compatible? }

  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:options) { {} }
  let(:initialize_block) do
    proc do
      config.action_cable.disable_request_forgery_protection = true
    end
  end
  let!(:fake_client_support) do
    allow(::WebSocket::Driver).to receive(:websocket?).and_return(true)
  end

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rails, options
      c.tracing.instrument :action_cable, options
    end

    rails_test_application.instance.routes.draw do
      mount ActionCable.server => '/cable'
    end

    raise_on_rails_deprecation!

    # ActionCable background threads that can't be finished
    allow(ActionCable.server).to receive(:call).and_wrap_original do |method, *args, &block|
      ThreadHelpers.with_leaky_thread_creation(:action_cable) do
        method.call(*args, &block)
      end
    end
  end

  context 'on ActionCable connection request' do
    subject! { get '/cable' }

    it 'overrides trace resource' do
      action_cable, rack = spans

      expect(action_cable.name).to eq('action_cable.on_open')
      expect(action_cable.resource).to eq('ActionCable::Connection::Base#on_open')

      expect(trace.name).to eq('rack.request')
      expect(trace.resource).to eq('ActionCable::Connection::Base#on_open')

      expect(rack.name).to eq('rack.request')
      expect(rack.resource).to eq('ActionCable::Connection::Base#on_open')
    end
  end
end
