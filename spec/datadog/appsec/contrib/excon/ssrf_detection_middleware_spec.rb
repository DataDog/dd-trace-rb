# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'excon'

RSpec.describe 'AppSec excon SSRF detection middleware' do
  let(:context) { instance_double(Datadog::AppSec::Context, run_rasp: waf_response) }
  let(:waf_response) { instance_double(Datadog::AppSec::SecurityEngine::Result::Ok, match?: false) }

  let(:client) do
    ::Excon.new('http://example.com', mock: true).tap do
      ::Excon.stub({method: :get, path: '/success'}, body: 'OK', status: 200)
    end
  end

  before do
    Datadog.configure do |c|
      c.appsec.enabled = true
      c.appsec.instrument :excon
    end

    allow(Datadog::AppSec).to receive(:active_context).and_return(context)
  end

  after do
    Datadog.configuration.reset!
  end

  context 'when RASP is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(false)
    end

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.get(path: '/success')
    end
  end

  context 'when there is no active context' do
    let(:context) { nil }

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.get(path: '/success')
    end
  end

  context 'when RASP is enabled' do
    before do
      allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(true)
    end

    it 'calls waf with correct arguments when making a request' do
      expect(Datadog::AppSec.active_context).to(
        receive(:run_rasp).with(
          Datadog::AppSec::Ext::RASP_SSRF,
          {},
          {'server.io.net.url' => 'http://example.com/success'},
          Datadog.configuration.appsec.waf_timeout
        )
      )

      client.get(path: '/success')
    end

    it 'returns the http response' do
      response = client.get(path: '/success')

      expect(response.status).to eq(200)
      expect(response.body).to eq('OK')
    end
  end
end
