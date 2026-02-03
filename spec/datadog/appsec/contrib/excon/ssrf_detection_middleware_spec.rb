# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/counter_sampler'
require 'excon'
require 'stringio'
require 'tempfile'

RSpec.describe 'AppSec excon SSRF detection middleware' do
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
    ::Excon.new('http://example.com', mock: true).tap do
      ::Excon.stub(
        {method: :post, path: '/text-plain', query: 'z=1'},
        body: '{"response":"OK"}',
        status: 200,
        headers: {
          'Content-Type' => 'text/plain',
          'Set-Cookie' => ['a=1', 'b=2'],
          'Via' => ['1.1 foo.io', '2.2 bar.io'],
          'Age' => '1'
        }
      )
      ::Excon.stub(
        {method: :post, path: '/application-json'},
        body: '{"response":"OK"}',
        status: 200,
        headers: {'Content-Type' => 'application/json'}
      )
      ::Excon.stub(
        {method: :post, path: '/invalid-json'},
        body: 'not json',
        status: 200,
        headers: {'Content-Type' => 'application/json'}
      )
    end
  end

  before do
    Datadog.configure do |c|
      c.appsec.enabled = true
      c.appsec.instrument :excon
    end

    WebMock.disable_net_connect!(allow: agent_url)

    allow(Datadog::AppSec).to receive(:active_context).and_return(context)
    allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(true)
  end

  after do
    Datadog.configuration.reset!
    ::Excon.defaults[:middlewares].delete(Datadog::AppSec::Contrib::Excon::SSRFDetectionMiddleware)
  end

  context 'when RASP is disabled' do
    before { allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(false) }

    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.post(path: '/text-plain', query: 'z=1')
    end
  end

  context 'when there is no active context' do
    before { allow(Datadog::AppSec).to receive(:active_context).and_return(nil) }
    it 'does not call waf when making a request' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      client.post(path: '/text-plain', query: 'z=1')
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

      client.post(
        path: '/text-plain',
        query: 'z=1',
        headers: {'Cookie' => 'x=1; y=2', 'Accept' => 'text/plain, application/json', 'DNT' => '1'}
      )
    end

    it 'returns the http response' do
      response = client.post(path: '/text-plain', query: 'z=1')

      expect(response.status).to eq(200)
      expect(response.body).to eq('{"response":"OK"}')
    end
  end

  context 'when request body is nil' do
    before do
      client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: nil)
    end

    it 'excludes body from ephemeral data' do
      expect(context).to have_received(:run_rasp).with(
        'ssrf', {}, hash_not_including('server.io.net.request.body'), anything, phase: 'request'
      )
    end
  end

  context 'when request body is a String' do
    context 'when JSON is valid' do
      before do
        client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: '{"key":"value"}')
      end

      it 'includes parsed body in ephemeral data' do
        expect(context).to have_received(:run_rasp).with(
          'ssrf', {}, hash_including('server.io.net.request.body' => {'key' => 'value'}), anything, phase: 'request'
        )
      end
    end

    context 'when JSON is invalid' do
      before do
        allow(Datadog::AppSec.telemetry).to receive(:report)

        client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: 'not json')
      end

      it 'does not include body in ephemeral data and reports error to telemetry' do
        expect(context).to have_received(:run_rasp)
          .with('ssrf', {}, hash_not_including('server.io.net.request.body'), anything, phase: 'request')

        expect(Datadog::AppSec.telemetry).to have_received(:report)
          .with(an_instance_of(JSON::ParserError), description: 'AppSec: Failed to parse body')
      end
    end
  end

  context 'when request body is a StringIO' do
    it 'includes parsed body in ephemeral data' do
      client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: StringIO.new('{"io":"data"}'))

      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_including('server.io.net.request.body' => {'io' => 'data'}), anything, phase: 'request')
    end
  end

  context 'when request body is an IO object' do
    before do
      client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: body)
    end

    after { body.close! }

    let(:body) do
      Tempfile.new('excon_body').tap do |f|
        f.write('{"file":"content"}')
        f.rewind
      end
    end

    it 'includes parsed body in ephemeral data' do
      expect(context).to have_received(:run_rasp).with(
        'ssrf', {}, hash_including('server.io.net.request.body' => {'file' => 'content'}), anything, phase: 'request'
      )
    end
  end

  context 'when request content-type is not JSON' do
    before do
      client.post(path: '/application-json', headers: {'Content-Type' => 'text/plain'}, body: '{"key":"value"}')
    end

    it 'does not include body in ephemeral data' do
      expect(context).to have_received(:run_rasp).with('ssrf', {}, anything, anything, phase: 'request')
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.request.body'), anything, phase: 'response')
    end
  end

  context 'when request content-type is application/x-www-form-urlencoded' do
    before do
      client.post(
        path: '/application-json',
        headers: {'Content-Type' => 'application/x-www-form-urlencoded'},
        body: 'key=value&foo=bar'
      )
    end

    it 'includes parsed body in ephemeral data' do
      expect(context).to have_received(:run_rasp).with(
        'ssrf', {}, hash_including('server.io.net.request.body' => {'key' => 'value', 'foo' => 'bar'}), anything, phase: 'request'
      )
    end
  end

  context 'when response body is valid JSON' do
    before { client.post(path: '/application-json') }

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

      client.post(path: '/invalid-json')
    end

    it 'does not include body in ephemeral data and reports error to telemetry' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.response.body'), anything, phase: 'response')

      expect(Datadog::AppSec.telemetry).to have_received(:report)
        .with(an_instance_of(JSON::ParserError), description: 'AppSec: Failed to parse body')
    end
  end

  context 'when response content-type is not JSON' do
    before do
      client.post(path: '/text-plain', query: 'z=1')
    end

    it 'does not include body in ephemeral data' do
      expect(context).to have_received(:run_rasp)
        .with('ssrf', {}, hash_not_including('server.io.net.response.body'), anything, phase: 'response')
    end
  end

  describe 'downstream body analysis sampling' do
    context 'when max_requests is 1' do
      before do
        Datadog.configuration.appsec.api_security.downstream_body_analysis.max_requests = 1
        Datadog.configuration.appsec.api_security.downstream_body_analysis.sample_rate = 1.0

        client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: '{"r":"1"}')
        client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: '{"r":"2"}')
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

    context 'when sample_rate is 0.5' do
      before do
        Datadog.configuration.appsec.api_security.downstream_body_analysis.max_requests = 5
        Datadog.configuration.appsec.api_security.downstream_body_analysis.sample_rate = 0.5

        client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: '{"r":"1"}')
        client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: '{"r":"2"}')
        client.post(path: '/application-json', headers: {'Content-Type' => 'application/json'}, body: '{"r":"3"}')
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
  end
end
