require 'datadog/tracing/contrib/graphql/support/application'

require 'datadog/tracing'
require 'datadog/appsec'

require 'json'

RSpec.describe 'GraphQL integration tests',
  skip: Gem::Version.new(::GraphQL::VERSION) < Gem::Version.new('2.0.19') do
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
        c.tracing.instrument :graphql, with_unified_tracer: true

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

      context 'with tracing and appsec enabled' do
        context 'with a valid query' do
          it do
            post '/graphql', query: '{ user(id: 1) { name } }'
            expect(last_response.body).to eq({ 'data' => { 'user' => { 'name' => 'Bits' } } }.to_json)
            # Flaky with GraphQL 2.3 using rake
            # Bug introduced in GraphQL Ruby 2.2.11
            expect(spans).to include(
              an_object_having_attributes(
                name: 'graphql.parse',
              ),
              an_object_having_attributes(
                name: 'graphql.execute_multiplex',
              ),
              an_object_having_attributes(
                name: 'graphql.execute',
              )
            )
          end
        end

        context 'with an invalid query' do
          it do
            post '/graphql', query: '{ error(id: 1) { name } }'
            expect(JSON.parse(last_response.body)['errors'][0]['message']).to eq(
              'Field \'error\' doesn\'t exist on type \'TestGraphQLQuery\''
            )
            expect(spans).to include(
              an_object_having_attributes(
                name: 'graphql.parse',
              ),
              an_object_having_attributes(
                name: 'graphql.execute_multiplex',
              )
            )
            expect(spans).not_to include(
              an_object_having_attributes(
                name: 'graphql.execute',
              )
            )
          end
        end

        context 'with a valid multiplex' do
          it do
            post '/graphql',
              _json: [
                { query: '{ user(id: 1) { name } }' },
                { query: '{ user(id: 10) { name } }' }
              ]
            expect(last_response.body).to eq(
              [
                { 'data' => { 'user' => { 'name' => 'Bits' } } },
                { 'data' => { 'user' => { 'name' => 'Caniche' } } }
              ].to_json
            )
          end
        end
      end
    end
  end
