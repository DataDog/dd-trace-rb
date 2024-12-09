# typed: ignore

require 'datadog'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/analytics_examples'
require 'rack/test'
require 'roda'
require 'datadog/tracing/contrib/support/spec_helper'

RSpec.describe 'Roda instrumentation' do
  include Rack::Test::Methods
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :roda, configuration_options
    end
  end

  around do |example|
    Datadog.registry[:roda].reset_configuration!
    example.run
    Datadog.registry[:roda].reset_configuration!
  end

  shared_context 'basic roda app' do
    let(:app) do
      Class.new(Roda) do
        use Datadog::Tracing::Contrib::Rack::TraceMiddleware
        plugin :all_verbs
        route do |r|
          r.root do
            r.get do
              'Hello World!'
            end
          end
          r.is 'articles' do
            r.get do
              'Articles'
            end
          end
          r.is 'worlds', Integer do
            r.put do
              'UPDATE'
            end
            r.get do
              "Hello, world #{r.params['world']}"
            end
          end
        end
      end
    end
  end

  shared_context 'Roda app with errors' do
    let(:app) do
      Class.new(Roda) do
        use Datadog::Tracing::Contrib::Rack::TraceMiddleware
        route do |r|
          r.root do
            r.get do
              r.halt([500, { 'content-type' => 'text/html' }, ['test']])
            end
          end

          r.is 'accident' do
            r.get do
              undefined_variable
            end
          end
        end
      end
    end
  end

  context 'when configured' do
    context 'with default settings' do
      context 'and a successful request is made' do
        include_context 'basic roda app'
        subject(:response) { get '/' }

        context 'for a basic GET endpoint' do
          it do
            expect(response.status).to eq(200)
            expect(spans).to have(2).items
            expect(spans[1].service).to eq('rspec')
            expect(spans[1].name).to eq('roda.request')
          end
        end

        context 'for a GET endpoint with an id' do
          subject(:params_response) { get 'worlds/1' }

          it do
            expect(response.status).to eq(200)
            expect(spans).to have(2).items
            expect(spans[1].service).to eq('rspec')
            expect(spans[1].name).to eq('roda.request')
          end
        end

        context 'for a GET endpoint with params' do
          let(:response) { get 'articles?id=1' }

          it do
            expect(response.status).to eq(200)
            expect(spans).to have(2).items
            expect(spans[1].service).to eq('rspec')
            expect(spans[1].name).to eq('roda.request')
          end
        end
      end

      context 'and an unsuccessful response occurs' do
        context 'with a 404' do
          include_context 'basic roda app'
          subject(:response) { get '/unsuccessful_endpoint' }
          it do
            expect(response.status).to eq(404)
            expect(spans).to have(2).items
            expect(spans[1].service).to eq('rspec')
            expect(spans[1].name).to eq('roda.request')
          end
        end

        context 'with a 500 from halt' do
          include_context 'Roda app with errors'
          subject(:response) { get '/' }
          it do
            expect(response.status).to eq(500)

            expect(spans).to have(2).items
            expect(spans[1].name).to eq('roda.request')
            expect(spans[1].status).to eq(1)
            expect(spans[1].service).to eq('rspec')
            expect(spans[1].get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('500')
          end
        end

        context 'with a 500 from user thrown errors' do
          include_context 'Roda app with errors'
          subject(:response) { get '/accident' }
          it do
            begin
              expect(response.status).to eq(500)
            rescue => e
              expect(e.class.to_s).to eq('NameError')
              expect(spans).to have(2).items
              expect(spans[1].name).to eq('roda.request')
              expect(spans[1].status).to eq(1)
              expect(spans[1].service).to eq('rspec')
              expect(spans[1].get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('500')
            end
          end
        end
      end

      context 'and the tracer is disabled' do
        include_context 'basic roda app'
        subject(:response) { get '/' }

        let(:tracer) { { enabled: false } }

        it do
          is_expected.to be_ok
          expect(spans).to eq([])
        end
      end
    end
  end
end
