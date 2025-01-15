# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/engine'
require 'datadog/appsec/contrib/rack/gateway/request'
require 'datadog/appsec/contrib/rack/reactive/request'
require 'datadog/appsec/reactive/shared_examples'

require 'rack'

RSpec.describe Datadog::AppSec::Contrib::Rack::Reactive::Request do
  let(:engine) { Datadog::AppSec::Reactive::Engine.new }
  let(:request) do
    Datadog::AppSec::Contrib::Rack::Gateway::Request.new(
      Rack::MockRequest.env_for(
        'http://example.com:8080/?a=foo',
        {
          'REQUEST_METHOD' => 'GET',
          'REMOTE_ADDR' => '10.10.10.10',
          'CONTENT_TYPE' => 'text/html',
          'HTTP_USER_AGENT' => 'foo',
          'HTTP_COOKIE' => 'foo=bar'
        }
      )
    )
  end

  let(:expected_headers_with_cookies) do
    { 'content-length' => '0', 'content-type' => 'text/html', 'user-agent' => 'foo', 'cookie' => 'foo=bar' }
  end

  let(:expected_headers_without_cookies) do
    { 'content-length' => '0', 'content-type' => 'text/html', 'user-agent' => 'foo' }
  end

  describe '.publish' do
    it 'propagates request attributes to the engine' do
      expect(engine).to receive(:publish).with('server.request.method', 'GET')
      expect(engine).to receive(:publish).with('request.query', { 'a' => ['foo'] })
      expect(engine).to receive(:publish).with('request.headers', expected_headers_with_cookies)
      expect(engine).to receive(:publish).with('request.uri.raw', '/?a=foo')
      expect(engine).to receive(:publish).with('request.cookies', { 'foo' => 'bar' })
      expect(engine).to receive(:publish).with('request.client_ip', '10.10.10.10')

      described_class.publish(engine, request)
    end
  end

  describe '.subscribe' do
    let(:appsec_context) { instance_double(Datadog::AppSec::Context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(engine).to receive(:subscribe).with(
          'request.headers',
          'request.uri.raw',
          'request.query',
          'request.cookies',
          'request.client_ip',
          'server.request.method',
        ).and_call_original
        expect(appsec_context).to_not receive(:run_waf)
        described_class.subscribe(engine, appsec_context)
      end
    end

    context 'all addresses have been published' do
      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: [], derivatives: [], timeout: false, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it 'does call the waf context with the right arguments' do
        expect(engine).to receive(:subscribe).and_call_original

        expected_waf_arguments = {
          'server.request.cookies' => { 'foo' => 'bar' },
          'server.request.query' => { 'a' => ['foo'] },
          'server.request.uri.raw' => '/?a=foo',
          'server.request.headers' => expected_headers_with_cookies,
          'server.request.headers.no_cookies' => expected_headers_without_cookies,
          'http.client_ip' => '10.10.10.10',
          'server.request.method' => 'GET',
        }

        expect(appsec_context).to receive(:run_waf)
          .with(expected_waf_arguments, {}, Datadog.configuration.appsec.waf_timeout)
          .and_return(waf_result)

        described_class.subscribe(engine, appsec_context)
        expect(described_class.publish(engine, request)).to be_nil
      end
    end

    it_behaves_like 'waf result' do
      let(:gateway) { request }
    end
  end
end
