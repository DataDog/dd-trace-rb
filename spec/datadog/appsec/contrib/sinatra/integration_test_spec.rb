# typed: ignore

require 'datadog/tracing/contrib/support/spec_helper'
require 'rack/test'

require 'securerandom'
require 'sinatra/base'

begin
  require 'rack/contrib/json_body_parser'
rescue LoadError
  # fallback for old rack-contrib
  require 'rack/contrib/post_body_content_type_parser'
end

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/sampling/ext'
require 'datadog/tracing/contrib/sinatra/ext'
require 'datadog/tracing/contrib/sinatra/tracer'

require 'datadog/appsec'
require 'datadog/appsec/contrib/rack/request_middleware'

RSpec.describe 'Sinatra integration tests' do
  include Rack::Test::Methods

  let(:sorted_spans) do
    chain = lambda do |start|
      loop.with_object([start]) do |_, o|
        # root reached (default)
        break o if o.last.parent_id == 0

        parent = spans.find { |span| span.span_id == o.last.parent_id }

        # root reached (distributed tracing)
        break o if parent.nil?

        o << parent
      end
    end
    sort = ->(list) { list.sort_by { |e| chain.call(e).count } }
    sort.call(spans)
  end

  let(:sinatra_span) { sorted_spans.reverse.find { |x| x.name == Datadog::Tracing::Contrib::Sinatra::Ext::SPAN_REQUEST } }
  let(:route_span) { sorted_spans.find { |x| x.name == Datadog::Tracing::Contrib::Sinatra::Ext::SPAN_ROUTE } }
  let(:rack_span) { sorted_spans.reverse.find { |x| x.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST } }

  let(:appsec_enabled) { true }
  let(:tracing_enabled) { true }

  before do
    Datadog.configure do |c|
      c.tracing.enabled = tracing_enabled
      c.tracing.instrument :sinatra

      c.appsec.enabled = appsec_enabled
      c.appsec.instrument :sinatra

      # TODO: test with c.appsec.instrument :rack
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:sinatra].reset_configuration!
    example.run
    Datadog.registry[:sinatra].reset_configuration!
  end

  context 'for an application' do
    # TODO: also test without Tracing: it should run without trace transport

    let(:middlewares) { [] }

    let(:app) do
      app_routes = routes
      app_middlewares = middlewares

      Class.new(Sinatra::Application) do
        app_middlewares.each { |m| use m }
        instance_exec(&app_routes)
      end
    end

    let(:triggers) do
      json = trace.send(:meta)['_dd.appsec.json']

      JSON.parse(json).fetch('triggers', []) if json
    end

    let(:span) { rack_span }

    shared_examples 'a GET 200 span' do
      it { expect(span.get_tag('http.method')).to eq('GET') }
      it { expect(span.get_tag('http.status_code')).to eq('200') }
      it { expect(span.status).to eq(0) }

      context 'with appsec disabled' do
        let(:appsec_enabled) { false }

        it { expect(span.get_tag('http.method')).to eq('GET') }
        it { expect(span.get_tag('http.status_code')).to eq('200') }
        it { expect(span.status).to eq(0) }
      end
    end

    shared_examples 'a GET 404 span' do
      it { expect(span.get_tag('http.method')).to eq('GET') }
      it { expect(span.get_tag('http.status_code')).to eq('404') }
      it { expect(span.status).to eq(0) }

      context 'with appsec disabled' do
        let(:appsec_enabled) { false }

        it { expect(span.get_tag('http.method')).to eq('GET') }
        it { expect(span.get_tag('http.status_code')).to eq('404') }
        it { expect(span.status).to eq(0) }
      end
    end

    shared_examples 'a POST 200 span' do
      it { expect(span.get_tag('http.method')).to eq('POST') }
      it { expect(span.get_tag('http.status_code')).to eq('200') }
      it { expect(span.status).to eq(0) }

      context 'with appsec disabled' do
        let(:appsec_enabled) { false }

        it { expect(span.get_tag('http.method')).to eq('POST') }
        it { expect(span.get_tag('http.status_code')).to eq('200') }
        it { expect(span.status).to eq(0) }
      end
    end

    shared_examples 'a trace without AppSec tags' do
      it { expect(trace.send(:metrics)['_dd.appsec.enabled']).to be_nil }
      it { expect(trace.send(:meta)['_dd.runtime_family']).to be_nil }
      it { expect(trace.send(:meta)['_dd.appsec.waf.version']).to be_nil }
    end

    shared_examples 'a trace with AppSec tags' do
      it { expect(trace.send(:metrics)['_dd.appsec.enabled']).to eq(1.0) }
      it { expect(trace.send(:meta)['_dd.runtime_family']).to eq('ruby') }
      it { expect(trace.send(:meta)['_dd.appsec.waf.version']).to match(/^\d+\.\d+\.\d+/) }

      context 'with appsec disabled' do
        let(:appsec_enabled) { false }

        it_behaves_like 'a trace without AppSec tags'
      end
    end

    shared_examples 'a trace without AppSec events' do
      it { expect(spans.select { |s| s.get_tag('appsec.event') }).to be_empty }
      it { expect(trace.send(:meta)['_dd.appsec.triggers']).to be_nil }
    end

    shared_examples 'a trace with AppSec events' do
      it { expect(spans.select { |s| s.get_tag('appsec.event') }).to_not be_empty }
      it { expect(trace.send(:meta)['_dd.appsec.json']).to be_a String }

      context 'with appsec disabled' do
        let(:appsec_enabled) { false }

        it_behaves_like 'a trace without AppSec events'
      end
    end

    context 'with a basic route' do
      let(:routes) do
        lambda do
          get '/success' do
            'ok'
          end

          post '/success' do
            'ok'
          end
        end
      end

      before do
        response
        expect(spans).to_not be_empty
      end

      describe 'GET request' do
        subject(:response) { get url, params, headers }

        let(:url) { '/success' }
        let(:params) { {} }
        let(:headers) { {} }

        context 'with a non-event-triggering request' do
          it { is_expected.to be_ok }

          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'
        end

        context 'with an event-triggering request in headers' do
          let(:headers) { { 'HTTP_USER_AGENT' => 'Nessus SOAP' } }

          it { is_expected.to be_ok }
          it { expect(triggers).to be_a Array }

          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
        end

        context 'with an event-triggering request in query string' do
          let(:params) { { q: '1 OR 1;' } }

          it { is_expected.to be_ok }

          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
        end

        context 'with an event-triggering request in route parameter' do
          let(:routes) do
            lambda do
              get '/success/:id' do
                'ok'
              end
            end
          end

          let(:url) { '/success/1%20OR%201;' }

          it { is_expected.to be_ok }

          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
        end

        context 'with an event-triggering response' do
          let(:url) { '/admin.php' } # well-known scanned path

          it { is_expected.to be_not_found }
          it { expect(triggers).to be_a Array }

          it_behaves_like 'a GET 404 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
        end
      end

      describe 'POST request' do
        subject(:response) { post url, params, headers }

        let(:url) { '/success' }
        let(:params) { {} }
        let(:headers) { {} }

        context 'with a non-event-triggering request' do
          it { is_expected.to be_ok }

          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'
        end

        context 'with an event-triggering request in application/x-www-form-url-encoded body' do
          let(:params) { { q: '1 OR 1;' } }

          it { is_expected.to be_ok }

          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
        end

        unless Gem.loaded_specs['rack-test'].version.to_s < '0.7'
          context 'with an event-triggering request in multipart/form-data body' do
            let(:params) { Rack::Test::Utils.build_multipart({ q: '1 OR 1;' }, true, true) }
            let(:headers) { { 'CONTENT_TYPE' => "multipart/form-data; boundary=#{Rack::Test::MULTIPART_BOUNDARY}" } }

            it { is_expected.to be_ok }

            it_behaves_like 'a POST 200 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'
          end
        end

        context 'with an event-triggering request as JSON' do
          let(:rack_contrib_body_parser) do
            if defined?(Rack::JSONBodyParser)
              Rack::JSONBodyParser
            else
              # fallback for old rack-contrib
              Rack::PostBodyContentTypeParser
            end
          end

          let(:middlewares) do
            [
              rack_contrib_body_parser,
            ]
          end

          let(:params) { JSON.generate('q' => '1 OR 1;') }
          let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }

          it { is_expected.to be_ok }

          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
        end
      end
    end
  end
end
