require 'datadog/tracing/contrib/support/spec_helper'
require 'rack/test'

require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Grape integration tests' do
  include Rack::Test::Methods

  let(:sorted_spans) do
    chain = lambda do |start|
      loop.with_object([start]) do |_, o|
        break o if o.last.parent_id == 0

        parent = spans.find { |span| span.id == o.last.parent_id }
        break o if parent.nil?

        o << parent
      end
    end
    sort = ->(list) { list.sort_by { |e| chain.call(e).count } }
    sort.call(spans)
  end

  let(:rack_span) { sorted_spans.reverse.find { |x| x.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST } }

  let(:tracing_enabled) { true }
  let(:appsec_enabled) { true }

  let(:api_security_enabled) { false }
  let(:api_security_sample) { 0 }

  before do
    Datadog.configure do |c|
      c.tracing.enabled = tracing_enabled
      c.tracing.instrument :rack

      c.appsec.enabled = appsec_enabled
      c.appsec.instrument :rack

      c.appsec.api_security.enabled = api_security_enabled
      c.appsec.api_security.sample_delay = api_security_sample.to_i
    end

    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?)
      .and_return(true)
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  context 'for a mounted Grape API' do
    let(:middlewares) do
      [
        Datadog::Tracing::Contrib::Rack::TraceMiddleware,
        Datadog::AppSec::Contrib::Rack::RequestMiddleware
      ]
    end

    let(:app) do
      skip 'grape gem not available' unless Gem.loaded_specs['grape']
      require 'grape'

      api_class = Class.new(Grape::API) do
        format :json
        get('/users/:id') { { ok: true } }
      end

      app_middlewares = middlewares

      Rack::Builder.new do
        app_middlewares.each { |m| use m }
        map '/' do
          run api_class
        end
      end.to_app
    end

    let(:service_span) do
      sorted_spans.reverse.find { |s| s.metrics.fetch('_dd.top_level', -1.0) > 0.0 }
    end

    let(:span) { rack_span }
    let(:remote_addr) { '127.0.0.1' }

    describe 'with sample_delay' do
      subject(:response) { get url, params, env }

      let(:api_security_enabled) { true }
      let(:api_security_sample) { 30 }

      let(:url) { '/users/123' }
      let(:params) { {} }
      let(:headers) { {} }
      let(:env) { { 'REMOTE_ADDR' => remote_addr }.merge!(headers) }

      it 'samples and caches check result' do
        get url, params, env
        first_span = spans.find { |s| s.name == 'rack.request' }
        expect(first_span.tags).to have_key('_dd.appsec.s.req.headers')

        clear_traces!

        get url, params, env
        second_span = spans.find { |s| s.name == 'rack.request' }
        expect(second_span.tags).not_to have_key('_dd.appsec.s.req.headers')
      end
    end
  end
end


