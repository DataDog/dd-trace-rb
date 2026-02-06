# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/counter_sampler'
require 'faraday'

RSpec.describe 'AppSec Faraday SSRF detection middleware' do
  let(:context) do
    instance_double(
      Datadog::AppSec::Context,
      run_rasp: waf_response,
      downstream_body_sampler: Datadog::AppSec::CounterSampler.new(1.0),
      state: {downstream_body_analyzed_count: 0}
    )
  end
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
        stub.post('/redirect-301') do |_|
          [301, {'Location' => 'http://example.com/application-json', 'Content-Type' => 'application/json'}, '{"redirect":"body"}']
        end
        stub.post('/redirect-302') do |_|
          [302, {'Location' => 'http://example.com/application-json', 'Content-Type' => 'text/html'}, '<html>Redirecting...</html>']
        end
        stub.post('/redirect-no-location') do |_|
          [301, {'Content-Type' => 'application/json'}, '{"redirect":"body"}']
        end
        stub.get('/redirect-chain-start') do |_|
          [301, {'Location' => 'http://example.com/redirect-chain-hop', 'Content-Type' => 'application/json'}, '{"hop":"1"}']
        end
        stub.get('/redirect-chain-hop') do |_|
          [302, {'Location' => '/redirect-chain-finish', 'Content-Type' => 'application/json'}, '{"hop":"2"}']
        end
        stub.get('/redirect-chain-finish') do |_|
          [200, {'Content-Type' => 'application/json'}, '{"final":"response"}']
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

    it 'does not include request body in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.request.body'), anything, phase: 'request')
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.response.body' => {'response' => 'OK'}), anything, phase: 'response')
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

  context 'when body sampling max_requests is 1' do
    before do
      Datadog.configuration.appsec.api_security.downstream_body_analysis.max_requests = 1
      Datadog.configuration.appsec.api_security.downstream_body_analysis.sample_rate = 1.0

      client.post('/application-json', '{"r":"1"}', {'Content-Type' => 'application/json'})
      client.post('/application-json', '{"r":"2"}', {'Content-Type' => 'application/json'})
    end

    let(:context) do
      instance_double(
        Datadog::AppSec::Context,
        run_rasp: waf_response,
        downstream_body_sampler: Datadog::AppSec::CounterSampler.new(1.0),
        state: {downstream_body_analyzed_count: 0}
      )
    end

    it 'analyzes body only for the first request' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.request.body' => {'r' => '1'}), anything, phase: 'request')

      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.request.body'), anything, phase: 'request')
    end
  end

  context 'when body sampling sample_rate is 0.5' do
    before do
      Datadog.configuration.appsec.api_security.downstream_body_analysis.max_requests = 5
      Datadog.configuration.appsec.api_security.downstream_body_analysis.sample_rate = 0.5

      client.post('/application-json', '{"r":"1"}', {'Content-Type' => 'application/json'})
      client.post('/application-json', '{"r":"2"}', {'Content-Type' => 'application/json'})
      client.post('/application-json', '{"r":"3"}', {'Content-Type' => 'application/json'})
    end

    let(:context) do
      instance_double(
        Datadog::AppSec::Context,
        run_rasp: waf_response,
        downstream_body_sampler: Datadog::AppSec::CounterSampler.new(0.5),
        state: {downstream_body_analyzed_count: 0}
      )
    end

    it 'analyzes request body only for the second request' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.request.body' => {'r' => '2'}), anything, phase: 'request')

      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.request.body'), anything, phase: 'request').twice
    end
  end

  context 'when response is 301 redirect with Location header' do
    before { client.post('/redirect-301', '{"key":"value"}', {'Content-Type' => 'application/json'}) }

    it 'includes request body in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.request.body' => {'key' => 'value'}), anything, phase: 'request')
    end

    it 'does not include redirect response body in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.response.body'), anything, phase: 'response')
    end

    it 'includes redirect response status and headers in ephemeral data' do
      expect(context).to have_received(:run_rasp).with(
        'ssrf',
        {},
        hash_including(
          'server.io.net.response.status' => '301',
          'server.io.net.response.headers' => hash_including('location' => 'http://example.com/application-json')
        ),
        anything,
        phase: 'response'
      )
    end
  end

  context 'when response is 302 redirect with non-JSON content-type' do
    before { client.post('/redirect-302', '{"key":"value"}', {'Content-Type' => 'application/json'}) }

    it 'does not include redirect response body in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.response.body'), anything, phase: 'response')
    end

    it 'includes redirect response status in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.response.status' => '302'), anything, phase: 'response')
    end
  end

  context 'when response is 301 without Location header' do
    before { client.post('/redirect-no-location', '{"key":"value"}', {'Content-Type' => 'application/json'}) }

    it 'includes response body in ephemeral data since it is not a true redirect' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.response.body' => {'redirect' => 'body'}), anything, phase: 'response')
    end
  end

  context 'when following redirect chain manually' do
    before do
      Datadog.configuration.appsec.api_security.downstream_body_analysis.max_requests = 10

      client.get('/redirect-chain-start')
      client.get('/redirect-chain-hop')
      client.get('/redirect-chain-finish')
    end

    it 'includes request URL for each hop in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.url' => 'http://example.com/redirect-chain-start'), anything, phase: 'request')
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.url' => 'http://example.com/redirect-chain-hop'), anything, phase: 'request')
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.url' => 'http://example.com/redirect-chain-finish'), anything, phase: 'request')
    end

    it 'does not include redirect response bodies in ephemeral data' do
      expect(context).not_to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.response.body' => {'hop' => '1'}), anything, phase: 'response')
      expect(context).not_to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.response.body' => {'hop' => '2'}), anything, phase: 'response')
    end

    it 'includes final response body in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.response.body' => {'final' => 'response'}), anything, phase: 'response')
    end

    it 'clears downstream_redirect_url state after following redirect chain' do
      expect(context.state[:downstream_redirect_url]).to be_nil
    end
  end

  context 'when using faraday-follow_redirects middleware', ruby: '> 2.5' do
    # NOTE: Hardcoded Ruby version limits in the gem
    require('faraday/follow_redirects') unless PlatformHelpers.ruby_version_matches?('2.5')

    before do
      Datadog.configuration.appsec.api_security.downstream_body_analysis.max_requests = 10
      client.get('/redirect-chain-start')
    end

    let(:client) do
      ::Faraday.new('http://example.com') do |faraday|
        faraday.response(:follow_redirects)
        faraday.adapter(:test) do |stub|
          stub.get('/redirect-chain-start') do |_|
            [301, {'Location' => 'http://example.com/redirect-chain-hop', 'Content-Type' => 'application/json'}, '{"hop":"1"}']
          end
          stub.get('/redirect-chain-hop') do |_|
            [302, {'Location' => '/redirect-chain-finish', 'Content-Type' => 'application/json'}, '{"hop":"2"}']
          end
          stub.get('/redirect-chain-finish') do |_|
            [200, {'Content-Type' => 'application/json'}, '{"final":"response"}']
          end
        end
      end
    end

    it 'includes request URL for each hop in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.url' => 'http://example.com/redirect-chain-start'), anything, phase: 'request')
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.url' => 'http://example.com/redirect-chain-hop'), anything, phase: 'request')
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.url' => 'http://example.com/redirect-chain-finish'), anything, phase: 'request')
    end

    it 'does not include redirect response bodies in ephemeral data' do
      expect(context).not_to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.response.body' => {'hop' => '1'}), anything, phase: 'response')
      expect(context).not_to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.response.body' => {'hop' => '2'}), anything, phase: 'response')
    end

    it 'includes final response body in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.response.body' => {'final' => 'response'}), anything, phase: 'response')
    end

    it 'clears downstream_redirect_url state after following redirect chain' do
      expect(context.state[:downstream_redirect_url]).to be_nil
    end
  end
end
