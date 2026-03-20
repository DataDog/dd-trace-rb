# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'
require 'rack'

RSpec.describe Datadog::AppSec::Contrib::Rack::RequestMiddleware do
  include Rack::Test::Methods

  before do
    Datadog.configure do |c|
      c.tracing.enabled = true
      c.tracing.instrument :rack

      c.appsec.enabled = true
      c.appsec.instrument :rack
      c.appsec.waf_timeout = 10_000_000
      c.appsec.ruleset = appsec_ruleset
      c.appsec.api_security.enabled = false
      c.appsec.api_security.sample_delay = 0.0

      c.remote.enabled = false
    end

    allow(Datadog::AppSec::APISecurity).to receive(:sample_trace?).and_return(true)
    allow(Datadog::AppSec::APISecurity).to receive(:sample?).and_return(true)

    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport)
      .to receive(:native_events_supported?).and_return(true)
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  let(:appsec_ruleset) { :recommended }

  let(:app) do
    app_routes = routes
    Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestMiddleware
      use Rack::ContentLength

      instance_eval(&app_routes)
    end.to_app
  end

  let(:service_span) { spans.find { |s| s.metrics.fetch('_dd.top_level', -1.0) > 0.0 } }

  let(:routes) do
    rack_response = response
    proc do
      map '/success' do
        run(proc { |_env| rack_response })
      end
    end
  end

  let(:response) { [200, {'content-type' => 'text/html', 'content-length' => '2'}, ['OK']] }

  describe 'response header tags' do
    context 'when request triggers no security event' do
      before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      it { expect(service_span.get_tag('http.response.headers.content-type')).to eq('text/html') }
      it { expect(service_span.get_tag('http.response.headers.content-length')).to eq('2') }
    end

    context 'when appsec is disabled' do
      before do
        Datadog.configuration.appsec.enabled = false
        get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1')
      end

      it { expect(service_span.get_tag('http.response.headers.content-length')).to be_nil }
    end

    context 'when request triggers a security event' do
      before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1', 'HTTP_USER_AGENT' => 'Nessus SOAP') }

      it { expect(service_span.get_tag('http.response.headers.content-type')).to eq('text/html') }
      it { expect(service_span.get_tag('http.response.headers.content-length')).to eq('2') }
    end

    context 'when request triggers a blocking event' do
      before { get("/success?q=1' OR '1'='1", {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:appsec_ruleset) do
        {
          version: '2.2',
          metadata: {rules_version: '1.4.1'},
          rules: [
            {
              id: 'crs-942-100',
              name: 'SQL Injection Attack Detected via libinjection',
              tags: {type: 'sql_injection', crs_id: '942100', category: 'attack_attempt'},
              conditions: [
                {
                  parameters: {inputs: [{address: 'server.request.query'}]},
                  operator: 'is_sqli'
                }
              ],
              transformers: ['removeNulls'],
              on_match: ['block']
            },
          ]
        }
      end

      it { expect(last_response.status).to eq(403) }
      it { expect(service_span.get_tag('http.response.headers.content-type')).to eq('application/json') }
      it { expect(service_span.get_tag('http.response.headers.content-length')).to match(/\A\d+\z/) }
    end

    context 'when response has no content-length header' do
      before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:response) { [200, {'content-type' => 'text/plain'}, ['hello']] }

      it { expect(service_span.get_tag('http.response.headers.content-length')).to eq('5') }
    end

    context 'when response body has multiple parts' do
      before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:response) { [200, {'content-type' => 'text/plain'}, ['hello', ' world']] }

      it { expect(service_span.get_tag('http.response.headers.content-length')).to eq('11') }
    end

    context 'when response has content-encoding header' do
      before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:response) { [200, {'content-type' => 'text/html', 'content-encoding' => 'gzip'}, ['OK']] }

      it { expect(service_span.get_tag('http.response.headers.content-encoding')).to eq('gzip') }
    end

    context 'when response has content-language header' do
      before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:response) { [200, {'content-type' => 'text/html', 'content-language' => 'en'}, ['OK']] }

      it { expect(service_span.get_tag('http.response.headers.content-language')).to eq('en') }
    end

    context 'when response has non-allowed headers' do
      before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:response) { [200, {'content-type' => 'text/html', 'x-custom' => 'secret'}, ['OK']] }

      it { expect(service_span.get_tag('http.response.headers.content-type')).to eq('text/html') }
      it { expect(service_span.get_tag('http.response.headers.x-custom')).to be_nil }
    end

    context 'without Rack::ContentLength middleware' do
      let(:app) do
        app_routes = routes
        Rack::Builder.new do
          use Datadog::Tracing::Contrib::Rack::TraceMiddleware
          use Datadog::AppSec::Contrib::Rack::RequestMiddleware

          instance_eval(&app_routes)
        end.to_app
      end

      context 'when response has no content-length header and body responds to to_ary' do
        before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

        let(:response) { [200, {'content-type' => 'text/plain'}, ['hello']] }

        it { expect(service_span.get_tag('http.response.headers.content-length')).to eq('5') }
      end

      context 'when response has no content-length header and body has multiple parts' do
        before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

        let(:response) { [200, {'content-type' => 'text/plain'}, ['hello', ' world']] }

        it { expect(service_span.get_tag('http.response.headers.content-length')).to eq('11') }
      end

      context 'when response has content-length header already set' do
        before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

        let(:response) { [200, {'content-type' => 'text/plain', 'content-length' => '99'}, ['hello']] }

        it { expect(service_span.get_tag('http.response.headers.content-length')).to eq('99') }
      end

      context 'when response body is a streaming body' do
        before { get('/success', {}, 'REMOTE_ADDR' => '127.0.0.1') }

        let(:response) { [200, {'content-type' => 'text/plain'}, ['hello'].each] }

        it { expect(service_span.get_tag('http.response.headers.content-length')).to be_nil }
      end
    end
  end
end
