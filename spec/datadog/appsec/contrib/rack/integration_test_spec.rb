require 'datadog/tracing/contrib/support/spec_helper'
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

  let(:appsec_enabled) { true }
  let(:tracing_enabled) { true }
  let(:appsec_ip_denylist) { nil }
  let(:appsec_user_id_denylist) { nil }
  let(:appsec_ruleset) { :recommended }

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
    Datadog.configure do |c|
      c.tracing.enabled = tracing_enabled
      c.tracing.instrument :rack

      c.appsec.enabled = appsec_enabled
      c.appsec.instrument :rack
      c.appsec.ip_denylist = appsec_ip_denylist
      c.appsec.user_id_denylist = appsec_user_id_denylist
      c.appsec.ruleset = appsec_ruleset
    end
  end

  after do
    Datadog::AppSec.settings.send(:reset!)
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
      json = trace.send(:meta)['_dd.appsec.json']

      JSON.parse(json).fetch('triggers', []) if json
    end

    let(:remote_addr) { '127.0.0.1' }
    let(:client_ip) { remote_addr }

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

    shared_examples 'a GET 403 span' do
      it { expect(span.get_tag('http.method')).to eq('GET') }
      it { expect(span.get_tag('http.status_code')).to eq('403') }
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

    shared_examples 'a POST 403 span' do
      it { expect(span.get_tag('http.method')).to eq('POST') }
      it { expect(span.get_tag('http.status_code')).to eq('403') }
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
      it { expect(span.send(:meta)['http.client_ip']).to eq nil }
    end

    shared_examples 'a trace with AppSec tags' do
      it { expect(trace.send(:metrics)['_dd.appsec.enabled']).to eq(1.0) }
      it { expect(trace.send(:meta)['_dd.runtime_family']).to eq('ruby') }
      it { expect(trace.send(:meta)['_dd.appsec.waf.version']).to match(/^\d+\.\d+\.\d+/) }
      it { expect(span.send(:meta)['http.client_ip']).to eq client_ip }

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
        proc do
          map '/success' do
            run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
          end

          map '/readme.md' do
            run(
              proc do |env|
                # When appsec is enabled we want to force the 404 to trigger a rule match
                if env['datadog.waf.context']
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
        end
      end

      before do
        response
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get url, params, env }

        let(:url) { '/success' }
        let(:params) { {} }
        let(:headers) { {} }
        let(:env) { { 'REMOTE_ADDR' => remote_addr }.merge!(headers) }

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

          context 'and a blocking rule' do
            let(:appsec_ruleset) { crs_942_100 }

            it { is_expected.to be_forbidden }

            it_behaves_like 'a GET 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'
          end
        end

        context 'with an event-triggering request in IP' do
          let(:client_ip) { '1.2.3.4' }
          let(:appsec_ip_denylist) { [client_ip] }
          let(:headers) { { 'HTTP_X_FORWARDED_FOR' => client_ip } }

          it { is_expected.to be_forbidden }

          it_behaves_like 'a GET 403 span'
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

          context 'and a blocking rule' do
            let(:appsec_ruleset) { nfd_000_002 }
            let(:url) { '/readme.md' }
            let(:appsec_enabled) { true }

            it { is_expected.to be_forbidden }

            it_behaves_like 'a GET 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'
          end
        end

        context 'with user blocking ID' do
          let(:url) { '/set_user' }

          it { is_expected.to be_ok }

          it_behaves_like 'a GET 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'

          context 'with an event-triggering user ID' do
            let(:appsec_user_id_denylist) { ['blocked-user-id'] }

            it { is_expected.to be_forbidden }

            it_behaves_like 'a GET 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'
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

          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'
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

          context 'and a blocking rule' do
            let(:appsec_ruleset) { crs_942_100 }

            it { is_expected.to be_forbidden }

            it_behaves_like 'a POST 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'
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

            it_behaves_like 'a POST 200 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'

            context 'and a blocking rule' do
              let(:appsec_ruleset) { crs_942_100 }

              it { is_expected.to be_forbidden }

              it_behaves_like 'a POST 403 span'
              it_behaves_like 'a trace with AppSec tags'
              it_behaves_like 'a trace with AppSec events'
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

          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'

          context 'and a blocking rule' do
            let(:appsec_ruleset) { crs_942_100 }

            it { is_expected.to be_forbidden }

            it_behaves_like 'a POST 403 span'
            it_behaves_like 'a trace with AppSec tags'
            it_behaves_like 'a trace with AppSec events'
          end
        end
      end
    end
  end
end
