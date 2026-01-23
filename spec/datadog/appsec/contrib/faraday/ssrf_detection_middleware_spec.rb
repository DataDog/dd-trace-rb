# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'faraday'

RSpec.describe 'AppSec Faraday SSRF detection middleware' do
  let(:context) { instance_double(Datadog::AppSec::Context, run_rasp: waf_response) }
  let(:waf_response) { instance_double(Datadog::AppSec::SecurityEngine::Result::Ok, match?: false) }

  let(:client) do
    ::Faraday.new('http://example.com') do |faraday|
      faraday.adapter(:test) do |stub|
        stub.post('/text-plain?z=1') do |_|
          [
            200,
            {
              'Content-Type' => 'text/plain',
              'Set-Cookie' => ['a=1', 'b=2'],
              'Via' => ['1.1 foo.io', '2.2 bar.io'],
              'Age' => '1'
            },
            '{"response":"OK"}'
          ]
        end
        stub.post('/application-json') do |_|
          [200, {'Content-Type' => 'application/json'}, '{"response":"OK"}']
        end
        stub.post('/invalid-json') do |_|
          [200, {'Content-Type' => 'application/json'}, 'not json']
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
    allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(true)
  end

  after { Datadog.configuration.reset! }

  context 'when RASP is disabled' do
    before { allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(false) }

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.post('/text-plain?z=1')
    end
  end

  context 'when there is no active context' do
    before { allow(Datadog::AppSec).to receive(:active_context).and_return(nil) }

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.post('/text-plain?z=1')
    end
  end

  context 'when RASP is enabled' do
    it 'calls waf with correct arguments when making a request' do
      expect(Datadog::AppSec.active_context).to receive(:run_rasp)
        .with(
          'ssrf',
          {},
          hash_including(
            'server.io.net.url' => 'http://example.com/text-plain?z=1',
            'server.io.net.request.method' => 'POST',
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

      client.post('/text-plain?z=1', nil, {'Cookie' => 'x=1; y=2', 'Accept' => 'text/plain, application/json', 'DNT' => '1'})
    end

    it 'returns the http response' do
      response = client.post('/text-plain?z=1')

      expect(response.status).to eq(200)
      expect(response.body).to eq('{"response":"OK"}')
    end
  end

  context 'when request body is nil' do
    before { client.post('/application-json', nil, {'Content-Type' => 'application/json'}) }

    it 'excludes body from ephemeral data' do
      expect(context).to have_received(:run_rasp).with(
        'ssrf', {}, hash_not_including('server.io.net.request.body'), anything, phase: 'request'
      )
    end
  end

  context 'when request body is a String' do
    context 'when JSON is valid' do
      before { client.post('/application-json', '{"key":"value"}', {'Content-Type' => 'application/json'}) }

      it 'includes parsed body in ephemeral data' do
        expect(context).to have_received(:run_rasp).with(
          'ssrf', {}, hash_including('server.io.net.request.body' => {'key' => 'value'}), anything, phase: 'request'
        )
      end
    end

    context 'when JSON is invalid' do
      before do
        allow(Datadog::AppSec.telemetry).to receive(:report)

        client.post('/application-json', 'not json', {'Content-Type' => 'application/json'})
      end

      it 'does not include body in ephemeral data and reports error to telemetry' do
        expect(context).to have_received(:run_rasp)
          .with('ssrf', {}, hash_not_including('server.io.net.request.body'), anything, phase: 'request')

        expect(Datadog::AppSec.telemetry).to have_received(:report)
          .with(an_instance_of(JSON::ParserError), description: 'AppSec: Failed to parse body')
      end
    end
  end

  context 'when request content-type is not JSON' do
    before { client.post('/application-json', '{"key":"value"}', {'Content-Type' => 'text/plain'}) }

    it 'does not include body in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.request.body'), anything, phase: 'request')
    end
  end

  context 'when request content-type is application/x-www-form-urlencoded' do
    before { client.post('/application-json', 'key=value&foo=bar', {'Content-Type' => 'application/x-www-form-urlencoded'}) }

    it 'includes parsed body in ephemeral data' do
      expect(context).to have_received(:run_rasp).with(
        'ssrf', {}, hash_including('server.io.net.request.body' => {'key' => 'value', 'foo' => 'bar'}), anything, phase: 'request'
      )
    end
  end

  context 'when response body is valid JSON' do
    before { client.post('/application-json') }

    it 'includes parsed body in ephemeral data' do
      expect(context).to have_received(:run_rasp).with('ssrf', {}, anything, anything, phase: 'request')
      expect(context).to have_received(:run_rasp).with(
        'ssrf', {}, hash_including('server.io.net.response.body' => {'response' => 'OK'}), anything, phase: 'response'
      )
    end
  end

  context 'when response body is invalid JSON' do
    before do
      allow(Datadog::AppSec.telemetry).to receive(:report)

      client.post('/invalid-json')
    end

    it 'does not include body in ephemeral data and reports error to telemetry' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.response.body'), anything, phase: 'response')

      expect(Datadog::AppSec.telemetry).to have_received(:report)
        .with(an_instance_of(JSON::ParserError), description: 'AppSec: Failed to parse body')
    end
  end

  context 'when response content-type is not JSON' do
    before { client.post('/text-plain?z=1') }

    it 'does not include body in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.response.body'), anything, phase: 'response')
    end
  end
end
