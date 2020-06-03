require 'spec_helper'
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

  let(:spans) { tracer.writer.spans(:keep) }
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
    let(:rack_span) { spans.find { |span| span.name == 'rack.request' } }
    let(:action_cable_span) { spans.find { |span| span.name == 'action_cable.on_open' } }

    it { expect(spans).to have(2).items }
    it { expect(rack_span).to_not be nil }
    it { expect(action_cable_span).to_not be nil }

    it 'overrides parent Rack resource' do
      expect(rack_span.resource).to eq('ActionCable::Connection::Base#on_open')
    end
  end
end
