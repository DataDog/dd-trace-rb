require 'datadog/tracing/contrib/graphql/support/application'

require 'datadog/appsec/contrib/support/integration/shared_examples'

require 'datadog/tracing'
require 'datadog/appsec'

require 'json'

RSpec.describe 'GraphQL integration tests',
  skip: Gem::Version.new(::GraphQL::VERSION) < Gem::Version.new('2.0.19') do
    let(:sorted_spans) do
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

    let(:rack_span) { sorted_spans.reverse.find { |x| x.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST } }

    let(:appsec_enabled) { true }
    let(:tracing_enabled) { true }
    let(:appsec_ruleset) { :recommended }
    let(:client_ip) { '127.0.0.1' }

    let(:blocking_testattack) do
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

    let(:nonblocking_testattack) do
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
            ]
          }
        ]
      }
    end

    before do
      File.write('test.json', '{"errors": [{"title": "Blocked", "detail": "Security provided by Datadog."}]}')

      Datadog.configure do |c|
        c.tracing.enabled = tracing_enabled
        c.tracing.instrument :graphql, with_unified_tracer: true

        c.appsec.enabled = appsec_enabled
        c.appsec.instrument :graphql
        c.appsec.instrument :rails
        c.appsec.instrument :rack
        c.appsec.ruleset = appsec_ruleset
        c.appsec.block.templates.json = 'test.json'
      end
    end

    after do
      File.delete('test.json')
      Datadog.configuration.reset!
      Datadog.registry[:graphql].reset_configuration!
    end

    context 'for an application' do
      include_context 'GraphQL test application'

      let(:service_span) do
        span = sorted_spans.reverse.find { |s| s.metrics.fetch('_dd.top_level', -1.0) > 0.0 }

        expect(span.name).to eq 'rack.request'

        span
      end

      let(:span) { rack_span }

      before do
        response
      end

      describe 'a basic query' do
        subject(:response) { post '/graphql', query: query }

        context 'with a non-triggering query' do
          let(:query) { '{ user(id: 1) { name } }' }

          it do
            expect(last_response.body).to eq({ 'data' => { 'user' => { 'name' => 'Bits' } } }.to_json)
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

          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'
        end

        context 'with a non-blocking query' do
          let(:appsec_ruleset) { nonblocking_testattack }
          let(:query) { '{ userByName(name: "$testattack") { id } }' }

          it do
            expect(last_response.body).to eq({ 'data' => { 'userByName' => { 'id' => '1' } } }.to_json)
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

          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
        end

        context 'with a blocking query' do
          let(:appsec_ruleset) { blocking_testattack }
          let(:query) { '{ userByName(name: "$testattack") { id } }' }

          it do
            expect(last_response.body).to eq(
              {
                'errors' => [{ 'title' => 'Blocked', 'detail' => 'Security provided by Datadog.' }]
              }.to_json
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

          # GraphQL errors should have no impact on the HTTP layer
          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
        end
      end

      describe 'a multiplex query' do
        subject(:response) { post '/graphql', _json: queries }

        context 'with a non-triggering multiplex' do
          let(:queries) do
            [
              {
                'query' => 'query { user(id: 1) { name } }',
                'variables' => {}
              },
              {
                'query' => 'query Test($name: String!) { userByName(name: $name) { id } }',
                'variables' => { 'name' => 'Caniche' }
              }
            ]
          end

          it do
            expect(last_response.body).to eq(
              [
                { 'data' => { 'user' => { 'name' => 'Bits' } } },
                { 'data' => { 'userByName' => { 'id' => '10' } } }
              ].to_json
            )
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

          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace without AppSec events'
        end

        context 'with a multiplex containing a non-blocking query' do
          let(:appsec_ruleset) { nonblocking_testattack }
          let(:queries) do
            [
              {
                'query' => 'query { user(id: 1) { name } }',
                'variables' => {}
              },
              {
                'query' => 'query Test($name: String!) { userByName(name: $name) { id } }',
                'variables' => { 'name' => '$testattack' }
              }
            ]
          end

          it do
            expect(last_response.body).to eq(
              [
                { 'data' => { 'user' => { 'name' => 'Bits' } } },
                { 'data' => { 'userByName' => { 'id' => '1' } } }
              ].to_json
            )
            expect(spans).to include(
              an_object_having_attributes(
                name: 'graphql.parse',
              )
            ).twice
            expect(spans).to include(
              an_object_having_attributes(
                name: 'graphql.execute_multiplex',
              )
            ).once
            expect(spans).to include(
              an_object_having_attributes(
                name: 'graphql.execute',
              )
            ).twice
          end

          it_behaves_like 'a POST 200 span'
          it_behaves_like 'a trace with AppSec tags'
          it_behaves_like 'a trace with AppSec events'
        end

        context 'with a multiplex containing a blocking query' do
          let(:appsec_ruleset) { blocking_testattack }
          let(:queries) do
            [
              {
                'query' => 'query Test($name: String!) { userByName(name: $name) { id } }',
                'variables' => { 'name' => '$testattack' }
              },
              {
                'query' => 'query { user(id: 1) { name } }',
                'variables' => {}
              }
            ]
          end

          it do
            expect(last_response.body).to eq(
              [
                { 'errors' => [{ 'title' => 'Blocked', 'detail' => 'Security provided by Datadog.' }] },
                { 'errors' => [{ 'title' => 'Blocked', 'detail' => 'Security provided by Datadog.' }] }
              ].to_json
            )
            expect(spans).to include(
              an_object_having_attributes(
                name: 'graphql.parse',
              )
            ).twice
            expect(spans).to include(
              an_object_having_attributes(
                name: 'graphql.execute_multiplex',
              )
            ).once
            expect(spans).not_to include(
              an_object_having_attributes(
                name: 'graphql.execute',
              )
            )
          end
        end
      end
    end
  end
