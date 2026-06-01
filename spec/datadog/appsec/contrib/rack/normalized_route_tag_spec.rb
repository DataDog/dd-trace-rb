# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'
require 'rack'

require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Normalized route tag' do
  include Rack::Test::Methods

  before do
    Datadog.configure do |c|
      c.tracing.enabled = true
      c.tracing.instrument :rack

      c.appsec.enabled = true
      c.appsec.instrument :rack
      c.appsec.waf_timeout = 10_000_000
      c.appsec.ruleset = :recommended
      c.appsec.api_security.enabled = false

      c.remote.enabled = false
    end

    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport)
      .to receive(:native_events_supported?).and_return(true)
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  let(:app) do
    app_routes = routes
    Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestMiddleware

      instance_eval(&app_routes)
    end.to_app
  end

  let(:service_span) { spans.find { |s| s.metrics.fetch('_dd.top_level', -1.0) > 0.0 } }

  let(:routes) do
    route_env = rack_env
    proc do
      run(proc do |env|
        env.merge!(route_env)
        [200, {'content-type' => 'text/plain'}, ['OK']]
      end)
    end
  end

  describe 'with Rails route object in env' do
    context 'when route has params and format absent' do
      before { get('/', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:rack_env) do
        {
          'datadog.action_dispatch.route' => route_object('/users/:id(.:format)'),
          'action_dispatch.request.path_parameters' => {id: '42', format: nil},
          'PATH_INFO' => '/users/42',
        }
      end

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to eq('/users/{id}') }
    end

    context 'when route has format present in URL' do
      before { get('/', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:rack_env) do
        {
          'datadog.action_dispatch.route' => route_object('/posts/:id(.:format)'),
          'action_dispatch.request.path_parameters' => {id: '1', format: 'json'},
          'PATH_INFO' => '/posts/1.json',
        }
      end

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to eq('/posts/{id+format}') }
    end

    context 'when route is static' do
      before { get('/', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:rack_env) do
        {
          'datadog.action_dispatch.route' => route_object('/health'),
          'action_dispatch.request.path_parameters' => {},
          'PATH_INFO' => '/health',
        }
      end

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to eq('/health') }
    end

    context 'when route has nested optionals with partial match' do
      before { get('/', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:rack_env) do
        {
          'datadog.action_dispatch.route' => route_object('/posts(/:year(/:month(/:day)))'),
          'action_dispatch.request.path_parameters' => {year: '2024'},
          'PATH_INFO' => '/posts/2024',
        }
      end

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to eq('/posts/{year}') }
    end
  end

  describe 'with Rails route_uri_pattern in env' do
    context 'when route has params' do
      before { get('/', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:rack_env) do
        {
          'action_dispatch.route_uri_pattern' => '/articles/:slug(.:format)',
          'action_dispatch.request.path_parameters' => {slug: 'hello-world', format: nil},
          'PATH_INFO' => '/articles/hello-world',
        }
      end

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to eq('/articles/{slug}') }
    end
  end

  describe 'with Sinatra route in env' do
    context 'when route has params' do
      before { get('/', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:rack_env) do
        {
          'sinatra.route' => 'GET /users/:id',
          'PATH_INFO' => '/users/42',
        }
      end

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to eq('/users/{id}') }
    end
  end

  describe 'with Grape route in env' do
    context 'when route has params' do
      before { get('/', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:rack_env) do
        pattern = double('Grape::Router::Pattern', origin: '/api/users/:id')
        route_info = double('Grape::Router::Route', pattern: pattern)
        {
          'grape.routing_args' => {route_info: route_info},
          'PATH_INFO' => '/api/users/42',
        }
      end

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to eq('/api/users/{id}') }
    end
  end

  describe 'with no route data' do
    context 'when env has no framework keys' do
      before do
        allow(Datadog::Tracing).to receive(:active_trace).and_call_original
        get('/', {}, 'REMOTE_ADDR' => '127.0.0.1')
      end

      let(:rack_env) { {} }

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to be_nil }
    end
  end

  describe 'with appsec disabled' do
    before do
      Datadog.configure do |c|
        c.appsec.enabled = false
      end
      get('/', {}, 'REMOTE_ADDR' => '127.0.0.1')
    end

    let(:rack_env) do
      {
        'datadog.action_dispatch.route' => route_object('/users/:id(.:format)'),
        'action_dispatch.request.path_parameters' => {id: '42', format: nil},
        'PATH_INFO' => '/users/42',
      }
    end

    it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to be_nil }
  end

  describe 'with mount prefix' do
    context 'when trace has TAG_ROUTE_PATH set' do
      before do
        get('/', {}, 'REMOTE_ADDR' => '127.0.0.1')
      end

      let(:routes) do
        route_env = rack_env
        proc do
          run(proc do |env|
            env.merge!(route_env)
            trace = Datadog::Tracing.active_trace
            trace&.set_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_ROUTE_PATH, '/api/v2')
            [200, {'content-type' => 'text/plain'}, ['OK']]
          end)
        end
      end

      let(:rack_env) do
        {
          'datadog.action_dispatch.route' => route_object('/users/:id(.:format)'),
          'action_dispatch.request.path_parameters' => {id: '42', format: nil},
          'PATH_INFO' => '/api/v2/users/42',
        }
      end

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to eq('/api/v2/users/{id}') }
    end

    context 'when SCRIPT_NAME is set and TAG_ROUTE_PATH is absent' do
      before { get('/', {}, 'REMOTE_ADDR' => '127.0.0.1') }

      let(:rack_env) do
        {
          'sinatra.route' => 'GET /users/:id',
          'PATH_INFO' => '/users/42',
          'SCRIPT_NAME' => '/myapp',
        }
      end

      it { expect(service_span.get_tag('_dd.appsec.normalized_route')).to eq('/myapp/users/{id}') }
    end
  end

  private

  def route_object(spec_string)
    spec = double('spec', to_s: spec_string)
    path = double('path', spec: spec)
    double('route', path: path)
  end
end
