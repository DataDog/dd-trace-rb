require 'datadog/tracing/contrib/graphql/support/application'

require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'GraphQL integration tests' do
  let(:appsec_enabled) { true }
  let(:tracing_enabled) { true }
  let(:appsec_ruleset) { :recommended }

  let(:block_testattack) do
    {
      'version' => '2.2',
      'metadata' => {
        'rules_version' => '1.4.1'
      },
      'rules' => [
        {
          id: 'custom-000-000',
          name: 'Test Blocking GraphQL WAF',
          tags: {
            type: 'attack_tool',
            category: 'attack_attempt',
            cwe: '200',
            capec: '1000/118/169',
            tool_name: 'Datadog Canary Test',
            confidence: '1'
          },
          conditions: [
            {
              parameters: {
                inputs: [
                  {
                    address: 'graphql.server.all_resolvers'
                  }
                ],
                options: {
                  enforce_word_boundary: true
                },
                list: [
                  '$testattack'
                ]
              },
              operator: 'phrase_match'
            }
          ],
          transformers: [
            'lowercase'
          ],
          on_match: [
            'block'
          ]
        }
      ]
    }
  end

  before do
    Datadog.configure do |c|
      c.tracing.enabled = tracing_enabled
      c.tracing.instrument :graphql

      c.appsec.enabled = appsec_enabled
      c.appsec.instrument :graphql
      c.appsec.ruleset = appsec_ruleset
    end
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:graphql].reset_configuration!
  end

  context 'for an application' do
    include_context 'GraphQL test application'

    context 'with a valid query' do
      it do
        post '/graphql', query: '{ user(id: 1) { name } }'
        expect(last_response.body).to eq({ 'data' => { 'user' => { 'name' => 'Bits' } } }.to_json)
      end
    end
  end
end
