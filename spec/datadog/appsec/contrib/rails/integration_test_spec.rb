# frozen_string_literal: true

require 'datadog/tracing/contrib/rails/rails_helper'
require 'datadog/appsec/contrib/support/integration/shared_examples'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Rails integration tests' do
  include Rack::Test::Methods

  # We send the trace to a mocked agent to verify that the trace includes the headers that we want
  # In the future, it might be a good idea to use the traces that the mocked agent
  # receives in the tests/shared examples
  let(:agent_http_client) do
    Datadog::Tracing::Transport::HTTP.default(agent_settings: test_agent_settings) do |t|
      t.adapter agent_http_adapter
    end
  end

  let(:agent_http_adapter) { Datadog::Core::Transport::HTTP::Adapters::Net.new(agent_settings) }

  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
      adapter: nil,
      ssl: false,
      uds_path: nil,
      hostname: 'localhost',
      port: 6218,
      timeout_seconds: 30,
    )
  end

  let(:sorted_spans) do
    # We must format the trace to have the same result as the agent
    # This is especially important for _sampling_priority_v1 metric
    Datadog::Tracing::Transport::TraceFormatter.format!(trace)

    chain = lambda do |start|
      loop.with_object([start]) do |_, o|
        # root reached (default)
        break o if o.last.parent_id == 0

        parent = spans.find { |span| span.id == o.last.parent_id }

        # root reached (distributed tracing)
        break o if parent.nil?

        o << parent
      end
    end
    sort = ->(list) { list.sort_by { |e| chain.call(e).count } }
    sort.call(spans)
  end

  let(:agent_tested_headers) { {} }

  let(:rack_span) { sorted_spans.reverse.find { |x| x.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST } }

  let(:tracing_enabled) { true }
  let(:appsec_enabled) { true }

  let(:appsec_instrument_rack) { false }

  let(:appsec_standalone_enabled) { false }
  let(:appsec_ip_denylist) { [] }
  let(:appsec_user_id_denylist) { [] }
  let(:appsec_ruleset) { :recommended }
  let(:api_security_enabled) { false }
  let(:api_security_sample) { 0.0 }

  let(:crs_942_100) do
    {
      'version' => '2.2',
      'metadata' => {
        'rules_version' => '1.4.1'
      },
      'rules' => [
        {
          'id' => 'crs-942-100',
          'name' => 'SQL Injection Attack Detected via libinjection',
          'tags' => {
            'type' => 'sql_injection',
            'crs_id' => '942100',
            'category' => 'attack_attempt'
          },
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'server.request.query'
                  },
                  {
                    'address' => 'server.request.body'
                  },
                  {
                    'address' => 'server.request.path_params'
                  },
                  {
                    'address' => 'grpc.server.request.message'
                  }
                ]
              },
              'operator' => 'is_sqli'
            }
          ],
          'transformers' => [
            'removeNulls'
          ],
          'on_match' => [
            'block'
          ]
        },
      ]
    }
  end

  before do
    # It may have been better to add this endpoint to the Rails app,
    # but I couldn't figure out how to call the Rails app from itself using Net::HTTP.
    # Creating a WebMock and stubbing it was easier.
    WebMock.enable!
    stub_request(:get, 'http://localhost:3000/returnheaders')
      .to_return do |request|
        {
          status: 200,
          body: request.headers.to_json,
          headers: { 'Content-Type' => 'application/json' }
        }
      end

    # Mocked agent with correct headers
    stub_request(:post, 'http://localhost:6218/v0.4/traces')
      .with do |request|
        agent_tested_headers <= request.headers
      end
      .to_return(status: 200)

    # DEV: Would it be faster to do another stub for requests that don't match the headers
    # rather than waiting for the TCP connection to fail?

    # TODO: Mocked agent that matches a given body, then use it in the shared examples,
    # That way it would be real integration tests

    Datadog.configure do |c|
      c.tracing.enabled = tracing_enabled

      c.tracing.instrument :rails
      c.tracing.instrument :http

      c.appsec.enabled = appsec_enabled

      c.appsec.instrument :rails
      c.appsec.instrument :rack if appsec_instrument_rack

      c.appsec.standalone.enabled = appsec_standalone_enabled
      c.appsec.waf_timeout = 10_000_000 # in us
      c.appsec.ip_denylist = appsec_ip_denylist
      c.appsec.user_id_denylist = appsec_user_id_denylist
      c.appsec.ruleset = appsec_ruleset
      c.appsec.api_security.enabled = api_security_enabled
      c.appsec.api_security.sample_rate = api_security_sample
    end
  end

  after do
    WebMock.reset!
    WebMock.disable!

    Datadog.configuration.reset!
    Datadog.registry[:rails].reset_configuration!
  end

  context 'for an application' do
    include_context 'Rails test application'

    let(:controllers) { [controller] }

    let(:controller) do
      stub_const(
        'TestController',
        Class.new(ActionController::Base) do
          # skip CSRF token check for non-GET requests
          begin
            if respond_to?(:skip_before_action)
              skip_before_action :verify_authenticity_token
            else
              skip_before_filter :verify_authenticity_token
            end
          rescue ArgumentError # :verify_authenticity_token might not be defined
            nil
          end

          def success
            head :ok
          end

          def set_user
            Datadog::Kit::Identity.set_user(Datadog::Tracing.active_trace, id: 'blocked-user-id')
            head :ok
          end

          def request_downstream
            uri = URI('http://localhost:3000/returnheaders')
            ext_request = nil
            ext_response = nil

            Net::HTTP.start(uri.host, uri.port) do |http|
              ext_request = Net::HTTP::Get.new('/returnheaders')

              ext_response = http.request(ext_request)
            end

            render json: ext_response.body, content_type: 'application/json'
          end
        end
      )
    end

    let(:triggers) do
      json = service_span.send(:meta)['_dd.appsec.json']

      JSON.parse(json).fetch('triggers', []) if json
    end

    let(:remote_addr) { '127.0.0.1' }
    let(:client_ip) { remote_addr }

    let(:service_span) do
      sorted_spans.reverse.find { |s| s.metrics.fetch('_dd.top_level', -1.0) > 0.0 }
    end

    let(:span) { rack_span }

    context 'with a basic route' do
      let(:routes) do
        {
          '/success' => 'test#success',
          [:post, '/success'] => 'test#success',
          '/set_user' => 'test#set_user',
          '/requestdownstream' => 'test#request_downstream',
        }
      end

      before do
        response
      end

      describe 'GET request' do
        subject(:response) { get url, params, env }

        let(:url) { '/success' }
        let(:params) { {} }
        let(:headers) { {} }
        let(:env) { { 'REMOTE_ADDR' => remote_addr }.merge!(headers) }

        context 'with a non-event-triggering request' do
          it { is_expected.to be_ok }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'
          it_behaves_like 'a trace with AppSec api security tags'
        end

        context 'with an event-triggering request in headers' do
          let(:headers) { { 'HTTP_USER_AGENT' => 'Nessus SOAP' } }

          it { is_expected.to be_ok }
          it { expect(triggers).to be_a Array }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
          it_behaves_like 'a trace with AppSec api security tags'
        end

        context 'with an event-triggering request in query string' do
          let(:params) { { q: '1 OR 1;' } }

          it { is_expected.to be_ok }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
          it_behaves_like 'a trace with AppSec api security tags'

          context 'and a blocking rule' do
            let(:appsec_ruleset) { crs_942_100 }

            it { is_expected.to be_forbidden }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a GET 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events', { blocking: true }
            it_behaves_like 'a trace with AppSec api security tags'
          end
        end

        context 'with an event-triggering request in route parameter' do
          let(:routes) do
            {
              '/success/:id' => 'test#success'
            }
          end

          let(:url) { '/success/1%20OR%201;' }

          it { is_expected.to be_ok }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
          it_behaves_like 'a trace with AppSec api security tags'

          context 'and a blocking rule' do
            let(:appsec_ruleset) { crs_942_100 }

            it { is_expected.to be_forbidden }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a GET 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events', { blocking: true }
            it_behaves_like 'a trace with AppSec api security tags'
          end
        end

        context 'with an event-triggering request in IP' do
          let(:client_ip) { '1.2.3.4' }
          let(:appsec_ip_denylist) { [client_ip] }
          let(:headers) { { 'HTTP_X_FORWARDED_FOR' => client_ip } }

          it { is_expected.to be_forbidden }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a GET 403 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events', { blocking: true }
          it_behaves_like 'a trace with AppSec api security tags'
        end

        context 'with an event-triggering response' do
          let(:url) { '/admin.php' } # well-known scanned path

          it { is_expected.to be_not_found }
          it { expect(triggers).to be_a Array }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a GET 404 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
          it_behaves_like 'a trace with AppSec api security tags'
        end

        context 'with user blocking ID' do
          let(:url) { '/set_user' }

          it { is_expected.to be_ok }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'
          it_behaves_like 'a trace with AppSec api security tags'

          context 'with an event-triggering user ID' do
            let(:appsec_user_id_denylist) { ['blocked-user-id'] }

            it { is_expected.to be_forbidden }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a GET 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'
            it_behaves_like 'a trace with AppSec api security tags'
          end
        end
      end

      describe 'POST request' do
        subject(:response) { post url, params, env }

        let(:url) { '/success' }
        let(:params) { {} }
        let(:headers) { {} }
        let(:env) { { 'REMOTE_ADDR' => remote_addr }.merge!(headers) }

        context 'with a non-event-triggering request' do
          it { is_expected.to be_ok }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'
          it_behaves_like 'a trace with AppSec api security tags'
        end

        context 'with an event-triggering request in application/x-www-form-url-encoded body' do
          let(:params) { { q: '1 OR 1;' } }

          it { is_expected.to be_ok }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
          it_behaves_like 'a trace with AppSec api security tags'

          context 'and a blocking rule' do
            let(:appsec_ruleset) { crs_942_100 }

            it { is_expected.to be_forbidden }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a POST 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events', { blocking: true }
            it_behaves_like 'a trace with AppSec api security tags'
          end
        end

        unless Gem.loaded_specs['rack-test'].version.to_s < '0.7'
          context 'with an event-triggering request in multipart/form-data body' do
            let(:params) { Rack::Test::Utils.build_multipart({ q: '1 OR 1;' }, true, true) }
            let(:headers) { { 'CONTENT_TYPE' => "multipart/form-data; boundary=#{Rack::Test::MULTIPART_BOUNDARY}" } }

            it { is_expected.to be_ok }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a POST 200 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'
            it_behaves_like 'a trace with AppSec api security tags'

            context 'and a blocking rule' do
              let(:appsec_ruleset) { crs_942_100 }

              it { is_expected.to be_forbidden }

              it_behaves_like 'normal with tracing disable'
              it_behaves_like 'a POST 403 span'
              it_behaves_like 'a trace with AppSec tags'
              it_behaves_like 'a trace with AppSec events', { blocking: true }
              it_behaves_like 'a trace with AppSec api security tags'
            end
          end
        end

        context 'with an event-triggering request as JSON' do
          let(:params) { JSON.generate('q' => '1 OR 1;') }
          let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }

          it { is_expected.to be_ok }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
          it_behaves_like 'a trace with AppSec api security tags'

          context 'and a blocking rule' do
            let(:appsec_ruleset) { crs_942_100 }

            it { is_expected.to be_forbidden }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a POST 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events', { blocking: true }
            it_behaves_like 'a trace with AppSec api security tags'
          end
        end
      end

      describe 'Nested apps' do
        let(:appsec_instrument_rack) { true }
        let(:middlewares) do
          [
            Datadog::Tracing::Contrib::Rack::TraceMiddleware,
            Datadog::AppSec::Contrib::Rack::RequestMiddleware
          ]
        end

        let(:rack_app) do
          app_middlewares = middlewares

          Rack::Builder.new do
            app_middlewares.each { |m| use m }
            map '/' do
              run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
            end
          end.to_app
        end

        let(:routes) do
          {
            [:mount, rack_app] => '/api',
          }
        end

        context 'GET request' do
          subject(:response) { get url, params, env }

          let(:url) { '/api' }
          let(:params) { {} }
          let(:headers) { {} }
          let(:env) { { 'REMOTE_ADDR' => remote_addr }.merge!(headers) }

          context 'with a non-event-triggering request' do
            it { is_expected.to be_ok }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a GET 200 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace without AppSec events'
          end

          context 'with an event-triggering request in headers' do
            let(:headers) { { 'HTTP_USER_AGENT' => 'Nessus SOAP' } }

            it { is_expected.to be_ok }
            it { expect(triggers).to be_a Array }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a GET 200 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'
          end

          context 'with an event-triggering request in query string' do
            let(:params) { { q: '1 OR 1;' } }

            it { is_expected.to be_ok }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a GET 200 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'

            context 'and a blocking rule' do
              let(:appsec_ruleset) { crs_942_100 }

              it { is_expected.to be_forbidden }

              it_behaves_like 'normal with tracing disable'
              it_behaves_like 'a GET 403 span'
              it_behaves_like 'a trace with AppSec tags'
              it_behaves_like 'a trace with AppSec events', { blocking: true }
            end
          end
        end
      end

      it_behaves_like 'appsec standalone billing'
    end
  end
end
