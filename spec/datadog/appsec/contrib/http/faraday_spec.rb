# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'faraday'

RSpec.describe 'AppSec Faraday integration' do
  let(:waf_response_double) { double(match?: false) }
  let(:active_context) { stub_const('Datadog::AppSec::Context', double(run_rasp: waf_response_double)) }

  let(:client) do
    ::Faraday.new('http://example.com') do |faraday|
      faraday.adapter(:test) do |stub|
        stub.get('/success') { |_| [200, {}, 'OK'] }
      end
    end
  end

  before do
    Datadog.configure do |c|
      c.appsec.enabled = true
      c.appsec.instrument :faraday
    end

    allow(Datadog::AppSec).to receive(:active_context).and_return(active_context)
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

      client.get('/success')
    end
  end

  context 'when there is no active context' do
    let(:active_context) { nil }

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.get('/success')
    end
  end

  context 'when RASP is enabled' do
    before do
      allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(true)
    end

    it 'calls waf with correct arguments when making a request' do
      expect(active_context).to(
        receive(:run_rasp).with(
          Datadog::AppSec::Ext::RASP_SSRF,
          {},
          { 'server.io.net.url' => 'http://example.com/success' },
          Datadog.configuration.appsec.waf_timeout
        )
      )

      client.get('/success')
    end

    it 'returns the http response' do
      response = client.get('/success')

      expect(response.status).to eq(200)
      expect(response.body).to eq('OK')
    end
  end
end
