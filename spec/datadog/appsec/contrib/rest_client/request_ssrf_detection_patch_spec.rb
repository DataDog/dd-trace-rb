# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'rest_client'

RSpec.describe 'RestClient::Request patch for SSRF detection' do
  let(:context) { instance_double(Datadog::AppSec::Context, run_rasp: waf_response) }
  let(:waf_response) { instance_double(Datadog::AppSec::SecurityEngine::Result::Ok, match?: false) }

  before do
    Datadog.configure do |c|
      c.appsec.enabled = true
      c.appsec.instrument :rest_client
    end

    allow(Datadog::AppSec).to receive(:active_context).and_return(context)

    WebMock.disable_net_connect!(allow: agent_url)
    WebMock.enable!(allow: agent_url)

    stub_request(:get, 'http://example.com/success').to_return(status: 200, body: 'OK')
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

      RestClient.get('http://example.com/success')
    end
  end

  context 'when there is no active context' do
    let(:context) { nil }

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      RestClient.get('http://example.com/success')
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
          { 'server.io.net.url' => 'http://example.com/success' },
          Datadog.configuration.appsec.waf_timeout
        )
      )

      RestClient.get('http://example.com/success')
    end

    it 'returns the http response' do
      response = RestClient.get('http://example.com/success')

      expect(response.code).to eq(200)
      expect(response.body).to eq('OK')
    end
  end
end
