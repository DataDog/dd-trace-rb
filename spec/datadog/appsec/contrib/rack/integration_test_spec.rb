require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/contrib/support/integration/shared_examples'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'securerandom'
require 'rack'

begin
  require 'rack/contrib/json_body_parser'
rescue LoadError
  # fallback for old rack-contrib
  require 'rack/contrib/post_body_content_type_parser'
end

require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Rack integration tests' do
  include Rack::Test::Methods

  # We send the trace to a mocked agent to verify that the trace includes the headers that we want
  # In the future, it might be a good idea to use the traces that the mocked agent
  # receives in the tests/shared examples
  let(:agent_http_client) do
    Datadog::Tracing::Transport::HTTP.default do |t|
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

  let(:agent_tested_headers) { {} }

  let(:tracing_enabled) { true }
  let(:appsec_enabled) { true }

  let(:appsec_standalone_enabled) { false }
  let(:remote_enabled) { false }
  let(:appsec_ip_passlist) { [] }
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

  let(:nfd_000_002) do
    {
      'version' => '2.2',
      'metadata' => {
        'rules_version' => '1.4.1'
      },
      'rules' => [
        {
          id: 'nfd-000-002',
          name: 'Detect failed attempt to fetch readme files',
          tags: {
            type: 'security_scanner',
            category: 'attack_attempt',
            confidence: '1'
          },
          conditions: [
            {
              operator: 'match_regex',
              parameters: {
                inputs: [
                  {
                    address: 'server.response.status'
                  }
                ],
                regex: '^404$',
                options: {
                  case_sensitive: true
                }
              }
            },
            {
              operator: 'match_regex',
              parameters: {
                inputs: [
                  {
                    address: 'server.request.uri.raw'
                  }
                ],
                regex: 'readme\\.[\\.a-z0-9]+$',
                options: {
                  case_sensitive: false
                }
              }
            }
          ],
          transformers: [],
          'on_match' => [
            'block'
          ]
        },
      ]
    }
  end

  before do
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

    # We must format the trace to have the same result as the agent
    # This is especially important for _sampling_priority_v1 metric

    unless remote_enabled
      Datadog.configure do |c|
        c.tracing.enabled = tracing_enabled

        c.tracing.instrument :rack
        c.tracing.instrument :http

        c.appsec.enabled = appsec_enabled

        c.appsec.instrument :rack

        c.appsec.standalone.enabled = appsec_standalone_enabled
        c.appsec.waf_timeout = 10_000_000 # in us
        c.appsec.ip_passlist = appsec_ip_passlist
        c.appsec.ip_denylist = appsec_ip_denylist
        c.appsec.user_id_denylist = appsec_user_id_denylist
        c.appsec.ruleset = appsec_ruleset
        c.appsec.api_security.enabled = api_security_enabled
        c.appsec.api_security.sample_rate = api_security_sample

        c.remote.enabled = remote_enabled
      end
    end
  end

  after do
    WebMock.reset!
    WebMock.disable!

    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  context 'for an application' do
    # TODO: also test without Tracing: it should run without trace transport

    let(:middlewares) do
      [
        Datadog::Tracing::Contrib::Rack::TraceMiddleware,
        Datadog::AppSec::Contrib::Rack::RequestMiddleware
      ]
    end

    let(:app) do
      app_routes = routes
      app_middlewares = middlewares

      Rack::Builder.new do
        app_middlewares.each { |m| use m }
        instance_eval(&app_routes)
      end.to_app
    end

    let(:triggers) do
      json = service_span.send(:meta)['_dd.appsec.json']

      JSON.parse(json).fetch('triggers', []) if json
    end

    let(:remote_addr) { '127.0.0.1' }
    let(:client_ip) { remote_addr }

    let(:service_span) do
      spans.find { |s| s.metrics.fetch('_dd.top_level', -1.0) > 0.0 }
    end

    let(:span) do
      Datadog::Tracing::Transport::TraceFormatter.format!(trace)
      spans.find { |s| s.name == 'rack.request' }
    end

    context 'with remote configuration' do
      before do
        if remote_enabled
          allow(Datadog::Core::Remote::Transport::HTTP).to receive(:v7).and_return(transport_v7)
          allow(Datadog::Core::Remote::Client).to receive(:new).and_return(client)
          allow(Datadog::Core::Remote::Negotiation).to receive(:new).and_return(negotiation)

          allow(client).to receive(:id).and_return(remote_client_id)
          allow(worker).to receive(:start).and_call_original
          allow(worker).to receive(:stop).and_call_original

          Datadog.configure do |c|
            c.remote.enabled = remote_enabled
            c.remote.boot_timeout_seconds = remote_boot_timeout
            c.remote.poll_interval_seconds = remote_poll_interval_seconds

            c.tracing.enabled = tracing_enabled
            c.tracing.instrument :rack

            c.appsec.enabled = appsec_enabled
            c.appsec.waf_timeout = 10_000_000 # in us
            c.appsec.instrument :rack
          end
        end
      end

      let(:routes) do
        proc do
          map '/success/' do
            run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
          end
        end
      end

      let(:remote_boot_timeout) { 1.0 }
      let(:remote_poll_interval_seconds) { 100.0 }
      let(:remote_client_id) { SecureRandom.uuid }

      let(:response) { get route }

      let(:remote_enabled) { true }

      context 'disabled' do
        let(:remote_enabled) { false }
        let(:route) { '/success/' }

        it 'has no remote configuration tags' do
          expect(response).to be_ok
          expect(spans).to have(1).items
          expect(span).to_not have_tag('_dd.rc.boot.time')
          expect(span).to_not have_tag('_dd.rc.boot.ready')
          expect(span).to_not have_tag('_dd.rc.boot.timeout')
          expect(span).to_not have_tag('_dd.rc.client_id')
          expect(span).to_not have_tag('_dd.rc.status')
          expect(span).to be_root_span
        end

        context 'without tracing' do
          let(:tracing_enabled) { false }
          let(:route) { '/success/' }

          it 'has no remote configuration tags' do
            expect(response).to be_ok
            expect(spans).to have(0).items
          end
        end
      end

      context 'enabled' do
        let(:remote_enabled) { true }
        let(:remote_boot_timeout) { 1.0 }
        let(:route) { '/success/' }

        let(:component) { Datadog::Core::Remote.active_remote }
        let(:worker) { component.instance_eval { @worker } }
        let(:client) { double('Client') }
        let(:transport_v7) { double('Transport') }
        let(:negotiation) { double('Negotiation') }

        context 'and responding' do
          before do
            allow(negotiation).to receive(:endpoint?).and_return(true)
            allow(worker).to receive(:call).and_call_original
            allow(client).to receive(:sync).and_invoke(remote_client_sync)

            # force evaluation to prevent locking from concurrent thread
            remote_client_sync_delay
          end

          let(:remote_client_sync) do
            lambda do
              sleep(remote_client_sync_delay) unless remote_client_sync_delay.nil?

              nil
            end
          end

          context 'faster than timeout' do
            let(:remote_client_sync_delay) { 0.1 }

            it 'has boot tags' do
              expect(response).to be_ok
              expect(spans).to have(1).items
              expect(span).to have_tag('_dd.rc.boot.time')
              expect(span.get_tag('_dd.rc.boot.time')).to be_a Float
              expect(span).to have_tag('_dd.rc.boot.ready')
              expect(span.get_tag('_dd.rc.boot.ready')).to eq 'true'
              expect(span).to_not have_tag('_dd.rc.boot.timeout')
              expect(span).to be_root_span
            end

            it 'has remote configuration tags' do
              expect(response).to be_ok
              expect(spans).to have(1).items
              expect(span).to have_tag('_dd.rc.client_id')
              expect(span.get_tag('_dd.rc.client_id')).to eq remote_client_id
              expect(span).to have_tag('_dd.rc.status')
              expect(span.get_tag('_dd.rc.status')).to eq 'ready'
            end

            context 'without tracing' do
              let(:tracing_enabled) { false }
              let(:route) { '/success/' }

              it 'has no remote configuration tags' do
                expect(response).to be_ok
                expect(spans).to have(0).items
              end
            end

            context 'on second request' do
              let(:remote_client_sync_delay) { remote_boot_timeout }

              let(:response) do
                get route
                sleep(2 * remote_client_sync_delay)
                get route
              end

              let(:last_span) { spans.last }

              it 'does not have boot tags' do
                expect(response).to be_ok
                expect(spans).to have(2).items
                expect(last_span).to_not have_tag('_dd.rc.boot.time')
                expect(last_span).to_not have_tag('_dd.rc.boot.ready')
                expect(last_span).to_not have_tag('_dd.rc.boot.timeout')
                expect(last_span).to be_root_span
              end

              it 'has remote configuration tags' do
                expect(response).to be_ok
                expect(spans).to have(2).items
                expect(last_span).to have_tag('_dd.rc.client_id')
                expect(last_span.get_tag('_dd.rc.client_id')).to eq remote_client_id
                expect(last_span).to have_tag('_dd.rc.status')
                expect(last_span.get_tag('_dd.rc.status')).to eq 'ready'
              end

              context 'without tracing' do
                let(:tracing_enabled) { false }
                let(:route) { '/success/' }

                it 'has no remote configuration tags' do
                  expect(response).to be_ok
                  expect(spans).to have(0).items
                end
              end
            end
          end

          context 'and responding slower than timeout' do
            let(:remote_client_sync_delay) { 2 * remote_boot_timeout }

            it 'has boot tags' do
              expect(response).to be_ok
              expect(spans).to have(1).items
              expect(span).to have_tag('_dd.rc.boot.time')
              expect(span.get_tag('_dd.rc.boot.time')).to be_a Float
              expect(span).to have_tag('_dd.rc.boot.timeout')
              expect(span.get_tag('_dd.rc.boot.timeout')).to eq 'true'
              expect(span).to_not have_tag('_dd.rc.boot.ready')
              expect(span).to be_root_span
            end

            it 'has remote configuration tags' do
              expect(response).to be_ok
              expect(spans).to have(1).items
              expect(span).to have_tag('_dd.rc.client_id')
              expect(span.get_tag('_dd.rc.client_id')).to eq remote_client_id
              expect(span).to have_tag('_dd.rc.status')
              expect(span.get_tag('_dd.rc.status')).to eq 'disconnected'
            end

            context 'without tracing' do
              let(:tracing_enabled) { false }
              let(:route) { '/success/' }

              it 'has no remote configuration tags' do
                expect(response).to be_ok
                expect(spans).to have(0).items
              end
            end

            context 'on second request' do
              context 'before sync' do
                let(:response) do
                  get route
                  get route
                end

                let(:last_span) { spans.last }

                it 'does not have boot tags' do
                  expect(response).to be_ok
                  expect(spans).to have(2).items
                  expect(last_span).to_not have_tag('_dd.rc.boot.time')
                  expect(last_span).to_not have_tag('_dd.rc.boot.ready')
                  expect(last_span).to_not have_tag('_dd.rc.boot.timeout')
                  expect(last_span).to be_root_span
                end

                it 'has remote configuration tags' do
                  expect(response).to be_ok
                  expect(spans).to have(2).items
                  expect(last_span).to have_tag('_dd.rc.client_id')
                  expect(last_span.get_tag('_dd.rc.client_id')).to eq remote_client_id
                  expect(last_span).to have_tag('_dd.rc.status')
                  expect(last_span.get_tag('_dd.rc.status')).to eq 'disconnected'
                end

                context 'without tracing' do
                  let(:tracing_enabled) { false }
                  let(:route) { '/success/' }

                  it 'has no remote configuration tags' do
                    expect(response).to be_ok
                    expect(spans).to have(0).items
                  end
                end
              end

              context 'after sync' do
                let(:remote_client_sync_delay) { 2 * remote_boot_timeout }

                let(:response) do
                  get route
                  sleep(2 * remote_client_sync_delay)
                  get route
                end

                let(:last_span) { spans.last }

                it 'does not have boot tags' do
                  expect(response).to be_ok
                  expect(spans).to have(2).items
                  expect(last_span).to_not have_tag('_dd.rc.boot.time')
                  expect(last_span).to_not have_tag('_dd.rc.boot.ready')
                  expect(last_span).to_not have_tag('_dd.rc.boot.timeout')
                  expect(last_span).to be_root_span
                end

                it 'has remote configuration tags' do
                  expect(response).to be_ok
                  expect(spans).to have(2).items
                  expect(last_span).to have_tag('_dd.rc.client_id')
                  expect(last_span.get_tag('_dd.rc.client_id')).to eq remote_client_id
                  expect(last_span).to have_tag('_dd.rc.status')
                  expect(last_span.get_tag('_dd.rc.status')).to eq 'ready'
                end

                context 'without tracing' do
                  let(:tracing_enabled) { false }
                  let(:route) { '/success/' }

                  it 'has no remote configuration tags' do
                    expect(response).to be_ok
                    expect(spans).to have(0).items
                  end
                end
              end
            end
          end
        end

        context 'not responding' do
          let(:exception) { Class.new(StandardError) }

          before do
            allow(negotiation).to receive(:endpoint?).and_return(true)
            allow(worker).to receive(:call).and_call_original
            allow(client).to receive(:sync).and_raise(exception, 'test')
            allow(Datadog.logger).to receive(:error).and_return(nil)
          end

          it 'has boot tags' do
            expect(response).to be_ok
            expect(spans).to have(1).items
            expect(span).to have_tag('_dd.rc.boot.time')
            expect(span.get_tag('_dd.rc.boot.time')).to be_a Float
            expect(span).to_not have_tag('_dd.rc.boot.timeout')
            expect(span).to have_tag('_dd.rc.boot.ready')
            expect(span.get_tag('_dd.rc.boot.ready')).to eq 'false'
            expect(span).to be_root_span
          end

          it 'has remote configuration tags' do
            expect(response).to be_ok
            expect(spans).to have(1).items
            expect(span).to have_tag('_dd.rc.client_id')
            expect(span.get_tag('_dd.rc.client_id')).to eq remote_client_id
            expect(span).to have_tag('_dd.rc.status')
            expect(span.get_tag('_dd.rc.status')).to eq 'disconnected'
          end

          context 'without tracing' do
            let(:tracing_enabled) { false }
            let(:route) { '/success/' }

            it 'has no remote configuration tags' do
              expect(response).to be_ok
              expect(spans).to have(0).items
            end
          end

          context 'on second request' do
            let(:remote_client_sync_delay) { remote_boot_timeout }

            let(:response) do
              get route
              sleep(2 * remote_client_sync_delay)
              get route
            end

            let(:last_span) { spans.last }

            it 'does not have boot tags' do
              expect(response).to be_ok
              expect(spans).to have(2).items
              expect(last_span).to_not have_tag('_dd.rc.boot.time')
              expect(last_span).to_not have_tag('_dd.rc.boot.ready')
              expect(last_span).to_not have_tag('_dd.rc.boot.timeout')
              expect(last_span).to be_root_span
            end

            it 'has remote configuration tags' do
              expect(response).to be_ok
              expect(spans).to have(2).items
              expect(last_span).to have_tag('_dd.rc.client_id')
              expect(last_span.get_tag('_dd.rc.client_id')).to eq remote_client_id
              expect(last_span).to have_tag('_dd.rc.status')
              expect(last_span.get_tag('_dd.rc.status')).to eq 'disconnected'
            end

            context 'without tracing' do
              let(:tracing_enabled) { false }
              let(:route) { '/success/' }

              it 'has no remote configuration tags' do
                expect(response).to be_ok
                expect(spans).to have(0).items
              end
            end
          end
        end
      end
    end

    context 'with a basic route' do
      let(:routes) do
        proc do
          map '/success' do
            run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
          end

          map '/readme.md' do
            run(
              proc do |env|
                # When appsec is enabled we want to force the 404 to trigger a rule match
                if env[Datadog::AppSec::Ext::SCOPE_KEY]
                  [404, { 'Content-Type' => 'text/html' }, ['NOT FOUND']]
                else
                  [200, { 'Content-Type' => 'text/html' }, ['OK']]
                end
              end
            )
          end

          map '/set_user' do
            run(
              proc do |_env|
                Datadog::Kit::Identity.set_user(Datadog::Tracing.active_trace, id: 'blocked-user-id')
                [200, { 'Content-Type' => 'text/html' }, ['OK']]
              end
            )
          end

          map '/requestdownstream' do
            run(
              proc do |_env|
                uri = URI('http://localhost:3000/returnheaders')
                ext_request = nil
                ext_response = nil

                Net::HTTP.start(uri.host, uri.port) do |http|
                  ext_request = Net::HTTP::Get.new(uri)

                  ext_response = http.request(ext_request)
                end

                [200, { 'Content-Type' => 'application/json' }, [ext_response.body]]
              end
            )
          end
        end
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

        context 'with WAF vendor headers' do
          let(:trace_tag_headers) do
            {
              'http.request.headers.x-amzn-trace-id' =>
                'Root=1-63441c4a-abcdef012345678912345678',

              'http.request.headers.cloudfront-viewer-ja3-fingerprint' =>
                'e7d705a3286e19ea42f587b344ee6865',

              'http.request.headers.cf-ray' =>
                '230b030023ae2822-SJC',

              'http.request.headers.x-cloud-trace-context' =>
                '105445aa7843bc8bf206b12000100000/1;o=1',

              'http.request.headers.x-appgw-trace-id' =>
                'ac882cd65a2712a0fe1289ec2bb6aee7',

              'http.request.headers.akamai-user-risk' =>
                'uuid=12345678-1234-1234-1234-123456789012;request-id=12345678;status=0;score=61;'\
                'risk=udfp:1234567890abcdefghijklmnopqrstuvwxyz1234/Hlunp=20057/H;trust=ugp:us;'\
                'general=di=1234567890abcdefghijklmnopqrstuvwxyz1234|do=Mac iOS 14|db=iOS Safari 14|aci=0;'\
                'allow=0;action=none',

              'http.request.headers.x-sigsci-requestid' =>
                '55c24b96ca84c02201000001',

              'http.request.headers.x-sigsci-tags' =>
                'SITE-FLAGGED-IP,IMPOSTOR'
            }
          end

          let(:headers) do
            {
              'HTTP_X_AMZN_TRACE_ID' =>
                'Root=1-63441c4a-abcdef012345678912345678',

              'HTTP_CLOUDFRONT_VIEWER_JA3_FINGERPRINT' =>
                'e7d705a3286e19ea42f587b344ee6865',

              'HTTP_CF_RAY' =>
                '230b030023ae2822-SJC',

              'HTTP_X_CLOUD_TRACE_CONTEXT' =>
                '105445aa7843bc8bf206b12000100000/1;o=1',

              'HTTP_X_APPGW_TRACE_ID' =>
                'ac882cd65a2712a0fe1289ec2bb6aee7',

              'HTTP_AKAMAI_USER_RISK' =>
                'uuid=12345678-1234-1234-1234-123456789012;request-id=12345678;status=0;score=61;'\
                'risk=udfp:1234567890abcdefghijklmnopqrstuvwxyz1234/Hlunp=20057/H;trust=ugp:us;'\
                'general=di=1234567890abcdefghijklmnopqrstuvwxyz1234|do=Mac iOS 14|db=iOS Safari 14|aci=0;'\
                'allow=0;action=none',

              'HTTP_X_SIGSCI_REQUESTID' =>
                '55c24b96ca84c02201000001',

              'HTTP_X_SIGSCI_TAGS' =>
                'SITE-FLAGGED-IP,IMPOSTOR'
            }
          end

          it { is_expected.to be_ok }

          it do
            trace_tag_headers.each do |header, value|
              expect(span.get_tag(header)).to eq(value)
            end
          end

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

          context 'and a blocking rule' do
            let(:appsec_ruleset) { crs_942_100 }

            it { is_expected.to be_forbidden }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a GET 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events', { blocking: true }
            it_behaves_like 'a trace with AppSec api security tags'

            context 'and a passlist' do
              let(:client_ip) { '1.2.3.4' }
              let(:appsec_ip_passlist) { [client_ip] }
              let(:headers) { { 'HTTP_X_FORWARDED_FOR' => client_ip } }

              it_behaves_like 'normal with tracing disable'
              it_behaves_like 'a GET 200 span'
              it_behaves_like 'a trace with AppSec tags'
              it_behaves_like 'a trace without AppSec events'
              it_behaves_like 'a trace with AppSec api security tags'
            end

            context 'and a monitoring passlist' do
              let(:client_ip) { '1.2.3.4' }
              let(:appsec_ip_passlist) { { monitor: [client_ip] } }
              let(:headers) { { 'HTTP_X_FORWARDED_FOR' => client_ip } }

              it_behaves_like 'normal with tracing disable'
              it_behaves_like 'a GET 200 span'
              it_behaves_like 'a trace with AppSec tags'
              it_behaves_like 'a trace with AppSec events'
              it_behaves_like 'a trace with AppSec api security tags'
            end
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
          it_behaves_like 'a trace with AppSec events'
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

          context 'and a blocking rule' do
            let(:appsec_ruleset) { nfd_000_002 }
            let(:url) { '/readme.md' }
            let(:appsec_enabled) { true }

            it { is_expected.to be_forbidden }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a GET 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events', { blocking: true }
            it_behaves_like 'a trace with AppSec api security tags'
          end
        end

        context 'with user blocking ID' do
          let(:url) { '/set_user' }

          it { is_expected.to be_ok }

          it_behaves_like 'normal with tracing disable'
          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'

          context 'with an event-triggering user ID' do
            let(:appsec_user_id_denylist) { ['blocked-user-id'] }

            it { is_expected.to be_forbidden }

            it_behaves_like 'normal with tracing disable'
            it_behaves_like 'a GET 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events', { blocking: true }
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

          let(:middlewares) do
            [
              Datadog::Tracing::Contrib::Rack::TraceMiddleware,
              Datadog::AppSec::Contrib::Rack::RequestMiddleware,
              Datadog::AppSec::Contrib::Rack::RequestBodyMiddleware,
            ]
          end

          it { is_expected.to be_ok }

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

            let(:middlewares) do
              [
                Datadog::Tracing::Contrib::Rack::TraceMiddleware,
                Datadog::AppSec::Contrib::Rack::RequestMiddleware,
                Datadog::AppSec::Contrib::Rack::RequestBodyMiddleware,
              ]
            end

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
              Datadog::Tracing::Contrib::Rack::TraceMiddleware,
              Datadog::AppSec::Contrib::Rack::RequestMiddleware,
              rack_contrib_body_parser,
              Datadog::AppSec::Contrib::Rack::RequestBodyMiddleware,
            ]
          end

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

      it_behaves_like 'appsec standalone billing'
    end
  end
end
