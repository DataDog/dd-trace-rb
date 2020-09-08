require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'

require 'ddtrace/contrib/rails/rails_helper'

begin
  require 'action_cable'
rescue LoadError
  puts 'ActionCable not supported in Rails < 5.0'
end

require 'websocket/driver'

RSpec.describe 'ActionCable Rack override' do
  before { skip('ActionCable not supported') unless Datadog::Contrib::ActionCable::Integration.compatible? }
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:options) { {} }

  before do
    Datadog.configure do |c|
      c.use :rails, options
      c.use :action_cable, options
    end

    rails_test_application.instance.routes.draw do
      mount ActionCable.server => '/cable'
    end
  end

  let(:initialize_block) do
    proc do
      config.action_cable.disable_request_forgery_protection = true
    end
  end

  let!(:fake_client_support) do
    allow(::WebSocket::Driver).to receive(:websocket?).and_return(true)
  end

  context 'on ActionCable connection request' do
    subject! { get '/cable' }

    it 'overrides parent Rack resource' do
      action_cable, rack = spans

      expect(action_cable.name).to eq('action_cable.on_open')
      expect(action_cable.resource).to eq('ActionCable::Connection::Base#on_open')

      expect(rack.name).to eq('rack.request')
      expect(rack.resource).to eq('ActionCable::Connection::Base#on_open')
    end
  end
end
