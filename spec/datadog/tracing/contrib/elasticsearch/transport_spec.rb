require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'time'
require 'elasticsearch'
require 'faraday'

require 'ddtrace'

RSpec.describe 'Elasticsearch::Transport::Client tracing' do
  before do
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  after do
    WebMock.allow_net_connect!
    WebMock.reset!
    WebMock.disable!
  end

  let(:host) { ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_ELASTICSEARCH_PORT', '1234').to_i }
  let(:server) { "http://#{host}:#{port}" }

  let(:client) { Elasticsearch::Client.new(url: server, adapter: :net_http) }
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :elasticsearch, configuration_options
    end

    # Mock realistic Elasticsearch verification response
    stub_request(:get, %r{#{Regexp.quote(server)}//?})
      .to_return(
        status: 200,
        headers: { 'x-elastic-product' => 'Elasticsearch', 'content-type' => 'application/yaml' },
        body: "version:\n  number: 8.0.0"
      )

    # Elasticsearch always sends one sanity request to `/` per client before executing the desired request.
    # @see https://github.com/elastic/elasticsearch-ruby/blob/ce84322759ff494764bbd096922faff998342197/elasticsearch/lib/elasticsearch.rb#L161
    client.perform_request('GET', '/')
    clear_traces!
  end

  after { Datadog.registry[:elasticsearch].reset_configuration! }

  context 'when configured with middleware' do
    let(:client) do
      Elasticsearch::Client.new url: server do |c|
        c.use middleware
      end
    end

    let(:middleware) do
      stub_const(
        'MyFaradayMiddleware',
        Class.new(Faraday::Middleware) do
          def call(env)
            @app.call(env)
          end
        end
      )
    end

    describe 'the handlers' do
      subject(:handlers) { client.transport.connections.first.connection.builder.handlers }

      it { is_expected.to include(middleware) }
    end
  end

  describe '#perform_request' do
    context 'with a' do
      context 'GET request' do
        subject(:response) { client.perform_request(method, path) }

        let(:method) { 'GET' }
        let(:path) { '_cluster/health' }

        before do
          stub_request(:get, "#{server}/#{path}").to_return(status: 200)
          expect(response.status).to eq(200)
        end

        it 'produces a well-formed trace' do
          expect(WebMock).to have_requested(:get, "#{server}/#{path}")
          expect(spans).to have(1).items
          expect(span.name).to eq('elasticsearch.query')
          expect(span.service).to eq('elasticsearch')
          expect(span.resource).to eq('GET _cluster/health')
          expect(span.get_tag('elasticsearch.url')).to eq('_cluster/health')
          expect(span.get_tag('elasticsearch.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq('200')
          expect(span.get_tag('elasticsearch.params')).to be nil
          expect(span.get_tag('elasticsearch.body')).to be nil
          expect(span.get_tag('out.host')).to eq(host)
          expect(span.get_tag('out.port')).to eq(port)
        end

        it_behaves_like 'a peer service span'
        it_behaves_like 'environment service name', 'DD_TRACE_ELASTICSEARCH_SERVICE_NAME'
      end

      context 'PUT request' do
        subject(:response) { client.perform_request(method, path, params, body) }

        let(:method) { 'PUT' }
        let(:path) { 'my/thing/1' }
        let(:params) { { refresh: true } }

        before do
          stub_request(:put, "#{server}/#{path}?refresh=true").with(body: body).to_return(status: 201)
          expect(response.status).to eq(201)
        end

        shared_examples_for 'a PUT request trace' do
          it do
            expect(WebMock).to have_requested(:put, "#{server}/#{path}?refresh=true")
            expect(spans).to have(1).items
            expect(span.name).to eq('elasticsearch.query')
            expect(span.service).to eq('elasticsearch')
            expect(span.resource).to eq('PUT my/thing/?')
            expect(span.get_tag('elasticsearch.url')).to eq(path)
            expect(span.get_tag('elasticsearch.method')).to eq('PUT')
            expect(span.get_tag('http.status_code')).to eq('201')
            expect(span.get_tag('elasticsearch.params')).to eq(params.to_json)
            expect(span.get_tag('elasticsearch.body')).to eq('{"data1":"?","data2":"?"}')
            expect(span.get_tag('out.host')).to eq(host)
            expect(span.get_tag('out.port')).to eq(port)
          end

          it_behaves_like 'a peer service span'
          it_behaves_like 'environment service name', 'DD_TRACE_ELASTICSEARCH_SERVICE_NAME'
        end

        context 'with Hash params' do
          let(:body) { '{"data1":"D1","data2":"D2"}' }

          it_behaves_like 'a PUT request trace'
        end

        context 'with encoded body' do
          let(:body) { { data1: 'D1', data2: 'D2' } }

          it_behaves_like 'a PUT request trace'
        end
      end
    end
  end

  describe 'client configuration override' do
    context 'when #service is overridden' do
      before { Datadog.configure_onto(client.transport, service_name: service_name) }

      let(:service_name) { 'bar' }

      describe 'then a GET request' do
        subject(:response) { client.perform_request(method, path) }

        let(:method) { 'GET' }
        let(:path) { '_cluster/health' }

        before do
          stub_request(:get, "#{server}/#{path}").to_return(status: 200)
        end

        it 'produces a well-formed trace' do
          expect(response.status).to eq(200)
          expect(WebMock).to have_requested(:get, "#{server}/#{path}")
          expect(spans).to have(1).items
          expect(span.name).to eq('elasticsearch.query')
          expect(span.service).to eq(service_name)
        end

        context 'configured at the Elasticsearch client level' do
          before do
            skip('Configuration through client object is not possible in Elasticsearch >= 8.0.0') if version_greater_than_8

            Datadog.configure_onto(client, service_name: 'custom')
          end

          let(:version_greater_than_8) { Gem::Version.new(::Elasticsearch::VERSION) >= Gem::Version.new('8.0.0') }

          it 'warns about deprecated configuration of the Elasticsearch client itself' do
            expect { response }.to emit_deprecation_warning(
              include('Providing configuration though the Elasticsearch client object is deprecated')
            )
          end
        end
      end
    end
  end
end
