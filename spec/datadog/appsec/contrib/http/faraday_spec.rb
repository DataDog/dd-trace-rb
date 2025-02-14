# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'faraday'

RSpec.describe 'AppSec Faraday integration' do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:ruleset) { Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry) }
  let(:processor) { Datadog::AppSec::Processor.new(ruleset: ruleset, telemetry: telemetry) }
  let(:context) { Datadog::AppSec::Context.new(trace, span, processor) }

  let(:span) { Datadog::Tracing::SpanOperation.new('root') }
  let(:trace) { Datadog::Tracing::TraceOperation.new }

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

    Datadog::AppSec::Context.activate(context)
  end

  after do
    Datadog.configuration.reset!

    Datadog::AppSec::Context.deactivate
    processor.finalize
  end

  context 'when RASP is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(false)
    end

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.get('/success')
    end

    it 'returns the http response' do
      response = client.get('/success')

      expect(response.status).to eq(200)
      expect(response.body).to eq('OK')
    end
  end

  context 'when there is no active context' do
    before do
      Datadog::AppSec::Context.deactivate
    end

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.get('/success')
    end

    it 'returns the http response' do
      response = client.get('/success')

      expect(response.status).to eq(200)
      expect(response.body).to eq('OK')
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
        ).and_call_original
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
