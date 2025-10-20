# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'rack/contrib'
require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Blocking with deny and pass list configuration' do
  include Rack::Test::Methods

  let(:trace_tagging_ruleset) do
    {
      'version' => '2.2',
      'metadata' => {'rules_version' => '1.25.1'},
      'rules' => [
        {
          'id' => 'arachni_rule',
          'name' => 'Arachni',
          'tags' => {'type' => 'security_scanner', 'category' => 'attack_attempt'},
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'server.request.headers.no_cookies',
                    'key_path' => ['user-agent']
                  }
                ],
                'regex' => '^Arachni\/v'
              },
              'operator' => 'match_regex'
            }
          ],
          'on_match' => ['block']
        }
      ],
      'rules_compat' => [
        {
          'id' => 'ttr-000-001',
          'name' => 'Trace Tagging Rule => Attributes, No Keep, No Event',
          'tags' => {'type' => 'security_scanner', 'category' => 'attack_attempt'},
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'server.request.headers.no_cookies',
                    'key_path' => ['user-agent']
                  }
                ],
                'regex' => '^TraceTagging\/v1'
              },
              'operator' => 'match_regex'
            }
          ],
          'output' => {
            'event' => false,
            'keep' => false,
            'attributes' => {
              '_dd.appsec.trace.integer' => {'value' => 1},
              '_dd.appsec.trace.agent' => {
                'address' => 'server.request.headers.no_cookies',
                'key_path' => ['user-agent']
              }
            }
          },
          'on_match' => []
        },
        {
          'id' => 'ttr-000-002',
          'name' => 'Trace Tagging Rule => Attributes, Keep, No Event',
          'tags' => {'type' => 'security_scanner', 'category' => 'attack_attempt'},
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'server.request.headers.no_cookies',
                    'key_path' => ['user-agent']
                  }
                ],
                'regex' => '^TraceTagging\/v2'
              },
              'operator' => 'match_regex'
            }
          ],
          'output' => {
            'event' => false,
            'keep' => true,
            'attributes' => {
              '_dd.appsec.trace.integer' => {'value' => 2},
              '_dd.appsec.trace.agent' => {
                'address' => 'server.request.headers.no_cookies',
                'key_path' => ['user-agent']
              }
            }
          },
          'on_match' => []
        },
        {
          'id' => 'ttr-000-003',
          'name' => 'Trace Tagging Rule => Attributes, Keep, Event',
          'tags' => {'type' => 'security_scanner', 'category' => 'attack_attempt'},
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'server.request.headers.no_cookies',
                    'key_path' => ['user-agent']
                  }
                ],
                'regex' => '^TraceTagging\/v3'
              },
              'operator' => 'match_regex'
            }
          ],
          'output' => {
            'event' => true,
            'keep' => true,
            'attributes' => {
              '_dd.appsec.trace.integer' => {'value' => 3},
              '_dd.appsec.trace.agent' => {
                'address' => 'server.request.headers.no_cookies',
                'key_path' => ['user-agent']
              }
            }
          },
          'on_match' => []
        },
        {
          'id' => 'ttr-000-004',
          'name' => 'Trace Tagging Rule => Attributes, No Keep, Event',
          'tags' => {'type' => 'security_scanner', 'category' => 'attack_attempt'},
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'server.request.headers.no_cookies',
                    'key_path' => ['user-agent']
                  }
                ],
                'regex' => '^TraceTagging\/v4'
              },
              'operator' => 'match_regex'
            }
          ],
          'output' => {
            'event' => true,
            'keep' => false,
            'attributes' => {
              '_dd.appsec.trace.integer' => {'value' => 4},
              '_dd.appsec.trace.agent' => {
                'address' => 'server.request.headers.no_cookies',
                'key_path' => ['user-agent']
              }
            }
          },
          'on_match' => []
        }
      ],
      'processors' => []
    }
  end

  let(:app) do
    stack = Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestMiddleware

      map '/test' do
        run ->(_) { [200, {'Content-Type' => 'text/html'}, ['OK']] }
      end
    end

    stack.to_app
  end

  let(:http_service_entry_span) do
    Datadog::Tracing::Transport::TraceFormatter.format!(trace)
    spans.find { |s| s.name == 'rack.request' }
  end

  before do
    Datadog.configure do |c|
      c.tracing.enabled = true

      c.appsec.enabled = true
      c.appsec.instrument :rack

      c.appsec.waf_timeout = 10_000_000 # in us
      c.appsec.ruleset = trace_tagging_ruleset
      c.appsec.api_security.enabled = true

      c.remote.enabled = false
    end

    # NOTE: Don't reach the agent in any way
    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?)
      .and_return(true)

    # NOTE: We want to exclude "initial" request behavior as it always alters the
    #       sampling priority
    allow_any_instance_of(Datadog::AppSec::Contrib::Rack::RequestMiddleware).to receive(:oneshot_tags_sent?)
      .and_return(true)
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  subject(:response) { last_response }

  context 'when rule configured to not generate event and not alter sampling' do
    before { get('/test', {}, {'HTTP_USER_AGENT' => 'TraceTagging/v1', 'HTTP_VIA' => 'test'}) }

    it 'does not alter sampling priority and does not include extended tags' do
      expect(response).to be_ok
      expect(http_service_entry_span.tags).not_to have_key('_dd.appsec.json')
      expect(http_service_entry_span.tags).not_to have_key('http.request.headers.via')
      expect(http_service_entry_span.tags).to include(
        '_sampling_priority_v1' => 1.0,
        '_dd.appsec.trace.integer' => 1.0,
        '_dd.appsec.trace.agent' => 'TraceTagging/v1'
      )
    end
  end

  context 'when rule configured to not generate event and to alter sampling' do
    before { get('/test', {}, {'HTTP_USER_AGENT' => 'TraceTagging/v2', 'HTTP_VIA' => 'test'}) }

    it 'alters sampling priority and includes extended tags' do
      expect(response).to be_ok
      expect(http_service_entry_span.tags).not_to have_key('_dd.appsec.json')
      expect(http_service_entry_span.tags).to include(
        '_sampling_priority_v1' => 2.0,
        '_dd.appsec.trace.integer' => 2.0,
        '_dd.appsec.trace.agent' => 'TraceTagging/v2',
        'http.request.headers.via' => 'test'
      )
    end
  end

  context 'when rule configured to generate event and to alter sampling' do
    before { get('/test', {}, {'HTTP_USER_AGENT' => 'TraceTagging/v3', 'HTTP_VIA' => 'test'}) }

    it 'alters sampling priority and includes extended tags' do
      expect(response).to be_ok
      expect(http_service_entry_span.tags).to have_key('_dd.appsec.json')
      expect(http_service_entry_span.tags).to include(
        '_sampling_priority_v1' => 2.0,
        '_dd.appsec.trace.integer' => 3.0,
        '_dd.appsec.trace.agent' => 'TraceTagging/v3',
        'http.request.headers.via' => 'test'
      )
    end
  end

  context 'when rule configured to generate event and to alter sampling' do
    before { get('/test', {}, {'HTTP_USER_AGENT' => 'TraceTagging/v4', 'HTTP_VIA' => 'test'}) }

    it 'alters sampling priority and includes extended tags' do
      expect(response).to be_ok
      expect(http_service_entry_span.tags).to have_key('_dd.appsec.json')
      expect(http_service_entry_span.tags).not_to have_key('http.request.headers.via')
      expect(http_service_entry_span.tags).to include(
        '_sampling_priority_v1' => 1.0,
        '_dd.appsec.trace.integer' => 4.0,
        '_dd.appsec.trace.agent' => 'TraceTagging/v4'
      )
    end
  end
end
