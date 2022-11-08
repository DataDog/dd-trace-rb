require 'ddtrace'
require 'datadog/tracing/contrib/analytics_examples'
require 'rack/test'
require 'roda'
require 'datadog/tracing/contrib/support/spec_helper'

RSpec.describe 'Roda instrumentation' do
  include Rack::Test::Methods

  let(:tracer) { tracer }
  let(:configuration_options) { { tracer: tracer } }
  let(:spans) { tracer.writer.spans }
  let(:span) { spans.first }

  before(:each) do
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

  shared_context 'Roda app with server error' do
    let(:app) do
      Class.new(Roda) do
        route do |r|
          r.root do
            r.get do
              r.halt([500, { 'Content-Type' => 'text/html' }, ['test']])
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
            expect(response.header).to eq('Content-Type' => 'text/html', 'Content-Length' => '12')
            expect(spans).to have(1).items
            expect(span.name).to eq('roda.request')
          end
        end

        context 'for a GET endpoint with an id' do
          subject(:params_response) { get 'worlds/1' }

          it do
            expect(response.status).to eq(200)
            expect(response.header).to eq('Content-Type' => 'text/html', 'Content-Length' => '12')
            expect(spans).to have(1).items
            expect(span.name).to eq('roda.request')
          end
        end

        context 'for a GET endpoint with params' do
          let(:response) { get 'articles?id=1' }

          it do
            expect(response.status).to eq(200)
            expect(response.header).to eq('Content-Type' => 'text/html', 'Content-Length' => '8')
            expect(spans).to have(1).items
            expect(span.name).to eq('roda.request')
          end
        end
      end

      context 'and an unsuccessful response occurs' do
        context 'with a 404' do
          include_context 'basic roda app'
          subject(:response) { get '/unsuccessful_endpoint' }
          it do
            expect(response.status).to eq(404)
            expect(response.header).to eq('Content-Type' => 'text/html', 'Content-Length' => '0')
            expect(spans).to have(1).items
            expect(span.name).to eq('roda.request')
          end
        end

        context 'with a 500' do
          include_context 'Roda app with server error'
          subject(:response) { get '/' }
          it do
            expect(response.status).to eq(500)
            expect(response.header).to eq('Content-Type' => 'text/html', 'Content-Length' => '4')
            expect(spans).to have(1).items
            expect(span.name).to eq('roda.request')
          end
        end
      end

      context 'and the tracer is disabled' do
        include_context 'basic roda app'
        subject(:response) { get '/' }

        let(:tracer) { tracer(enabled: false) }

        it do
          is_expected.to be_ok
          expect(spans).to be_empty
        end
      end
    end
  end
end
