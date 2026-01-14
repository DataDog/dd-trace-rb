# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'faraday'

RSpec.describe 'AppSec Faraday SSRF detection middleware' do
  let(:context) { instance_double(Datadog::AppSec::Context, run_rasp: waf_response) }
  let(:waf_response) { instance_double(Datadog::AppSec::SecurityEngine::Result::Ok, match?: false) }

  let(:client) do
    ::Faraday.new('http://example.com') do |faraday|
      faraday.adapter(:test) do |stub|
        stub.get('/success') do |_|
          [200, {'Set-Cookie' => ['a=1', 'b=2'], 'Via' => ['1.1 foo.io', '2.2 bar.io'], 'Age' => '1'}, 'OK']
        end
      end
    end
  end

  before do
    Datadog.configure do |c|
      c.appsec.enabled = true
      c.appsec.instrument :faraday
    end

    allow(Datadog::AppSec).to receive(:active_context).and_return(context)
  end

  after { Datadog.configuration.reset! }

  context 'when RASP is disabled' do
    before { allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(false) }

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.get('/success')
    end
  end

  context 'when there is no active context' do
    before { allow(Datadog::AppSec).to receive(:active_context).and_return(nil) }

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.get('/success')
    end
  end

  context 'when RASP is enabled' do
    before { allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(true) }

    it 'calls waf with correct arguments when making a request' do
      expect(Datadog::AppSec.active_context).to receive(:run_rasp)
        .with(
          'ssrf',
          {},
          hash_including(
            'server.io.net.url' => 'http://example.com/success?z=1',
            'server.io.net.request.method' => 'GET',
            'server.io.net.request.headers' => hash_including(
              'cookie' => 'x=1; y=2',
              'accept' => 'text/plain, application/json',
              'dnt' => '1'
            )
          ),
          kind_of(Integer),
          phase: 'request'
        )

      expect(Datadog::AppSec.active_context).to receive(:run_rasp)
        .with(
          'ssrf',
          {},
          hash_including(
            'server.io.net.response.status' => '200',
            'server.io.net.response.headers' => hash_including(
              'set-cookie' => 'a=1, b=2',
              'via' => '1.1 foo.io, 2.2 bar.io',
              'age' => '1'
            )
          ),
          kind_of(Integer),
          phase: 'response'
        )

      client.get(
        '/success?z=1', nil, {'Cookie' => 'x=1; y=2', 'Accept' => 'text/plain, application/json', 'DNT' => '1'}
      )
    end

    it 'returns the http response' do
      response = client.get('/success?z=1')

      expect(response.status).to eq(200)
      expect(response.body).to eq('OK')
    end
  end
end
