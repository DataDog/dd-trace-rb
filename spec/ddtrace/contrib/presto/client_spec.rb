require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'ddtrace'
require 'presto-client'
require 'ddtrace/contrib/analytics_examples'

RSpec.describe 'Presto::Client instrumentation' do
  let(:configuration_options) { {} }

  let(:client) do
    Presto::Client.new(
      server: "#{host}:#{port}",
      user: user,
      schema: schema,
      catalog: catalog,
      time_zone: time_zone,
      language: language,
      http_proxy: http_proxy,
      model_version: model_version
    )
  end
  let(:service) { 'presto' }
  let(:host) { ENV.fetch('TEST_PRESTO_HOST', 'localhost') }
  let(:port) { ENV.fetch('TEST_PRESTO_PORT', 8080) }
  let(:user) { 'test_user' }
  let(:schema) { 'test_schema' }
  let(:catalog) { 'memory' }
  let(:time_zone) { 'US/Pacific' }
  let(:language) { 'English' }
  let(:http_proxy) { 'proxy.example.com:8080' }
  let(:model_version) { '0.205' }

  let(:presto_client_gem_version) { Gem.loaded_specs['presto-client'].version }

  before(:each) do
    Datadog.configure do |c|
      c.use :presto, configuration_options
    end
  end

  def suppress_warnings
    original_verbosity = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = original_verbosity
  end

  around do |example|
    suppress_warnings do
      Datadog.registry[:presto].reset_configuration!
      example.run
      Datadog.registry[:presto].reset_configuration!
      Datadog.configuration.reset!
    end
  end

  context 'when the tracer is disabled' do
    before do
      Datadog.configure do |c|
        c.tracer.enabled = false
      end
    end

    it 'does not produce spans' do
      client.run('SELECT 1')
      expect(spans).to be_empty
    end
  end

  describe 'tracing' do
    shared_examples_for 'a Presto trace' do
      it 'has basic properties' do
        expect(spans).to have(1).items
        expect(span.service).to eq(service)
        expect(span.get_tag('presto.schema')).to eq(schema)
        expect(span.get_tag('presto.catalog')).to eq(catalog)
        expect(span.get_tag('presto.user')).to eq(user)
        expect(span.get_tag('presto.time_zone')).to eq(time_zone)
        expect(span.get_tag('presto.language')).to eq(language)
        expect(span.get_tag('presto.http_proxy')).to eq(http_proxy)
        expect(span.get_tag('presto.model_version')).to eq(model_version)
        expect(span.get_tag('out.host')).to eq("#{host}:#{port}")
      end
    end

    shared_examples_for 'a configurable Presto trace' do
      context 'when the client is configured' do
        context 'with a different service name' do
          let(:service) { 'presto-primary' }
          let(:configuration_options) { { service_name: service } }

          it_behaves_like 'a Presto trace'
        end

        context 'with a different schema' do
          let(:schema) { 'banana-schema' }

          it_behaves_like 'a Presto trace'
        end

        context 'with nil schema' do
          let(:schema) { nil }

          it_behaves_like 'a Presto trace'
        end

        context 'with an empty schema' do
          let(:schema) { '' }

          it_behaves_like 'a Presto trace'
        end

        context 'with a different catalog' do
          let(:catalog) { 'eatons' }

          it_behaves_like 'a Presto trace'
        end

        context 'with a nil catalog' do
          let(:schema) { nil }
          let(:catalog) { nil }

          it_behaves_like 'a Presto trace'
        end

        context 'with a different user' do
          let(:user) { 'banana' }

          it_behaves_like 'a Presto trace'
        end

        context 'with a different time zone' do
          let(:time_zone) { 'Antarctica/Troll' }

          it_behaves_like 'a Presto trace'
        end

        context 'with a nil time zone' do
          let(:time_zone) { nil }

          it_behaves_like 'a Presto trace'
        end

        context 'with a diferent language' do
          let(:language) { 'Français' }

          it_behaves_like 'a Presto trace'
        end

        context 'with a nil language' do
          let(:language) { nil }

          it_behaves_like 'a Presto trace'
        end

        context 'with a different http proxy' do
          let(:http_proxy) { 'proxy.bar.foo:8080' }

          it_behaves_like 'a Presto trace'
        end

        context 'with a nil http proxy' do
          let(:http_proxy) { nil }

          it_behaves_like 'a Presto trace'
        end

        context 'with a different model version' do
          let(:model_version) { '0.173' }

          it_behaves_like 'a Presto trace'
        end

        context 'with a nil model version' do
          let(:model_version) { nil }

          it_behaves_like 'a Presto trace'
        end
      end
    end

    shared_examples_for 'a synchronous query trace' do
      it 'is a synchronous query trace' do
        expect(span.get_tag('presto.query.async')).to eq('false')
      end
    end

    shared_examples_for 'an asynchronous query trace' do
      it 'is an asynchronous query trace' do
        expect(span.get_tag('presto.query.async')).to eq('true')
      end
    end

    shared_examples_for 'a sampled trace' do
      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::Presto::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::Presto::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', false
    end

    describe '#run operation' do
      before(:each) { client.run('SELECT 1') }

      it_behaves_like 'a Presto trace'
      it_behaves_like 'a configurable Presto trace'
      it_behaves_like 'a synchronous query trace'
      it_behaves_like 'a sampled trace'

      it 'has a query resource'  do
        expect(span.resource).to eq('SELECT 1')
      end

      it 'is SQL type' do
        expect(span.span_type).to eq('sql')
      end

      context 'a failed query' do
        before(:each) do
          clear_spans!
          begin
            client.run('SELECT banana')
          # rubocop:disable Lint/HandleExceptions
          rescue
            # do nothing
          end
          # rubocop:enable Lint/HandleExceptions
        end

        it_behaves_like 'a Presto trace'
        it_behaves_like 'a configurable Presto trace'

        it 'has a query resource'  do
          expect(span.resource).to eq('SELECT banana')
        end

        it 'is an error' do
          expect(span).to have_error
          expect(span).to have_error_type('Presto::Client::PrestoQueryError')
          expect(span).to have_error_message(/Column 'banana' cannot be resolved/)
        end
      end
    end

    describe '#query operation' do
      shared_examples_for 'a query trace' do
        it 'has a query resource' do
          expect(span.resource).to eq('SELECT 1')
        end

        it 'is SQL type' do
          expect(span.span_type).to eq('sql')
        end
      end

      context 'with no block paramter' do
        before(:each) { client.query('SELECT 1') }

        it_behaves_like 'a Presto trace'
        it_behaves_like 'a configurable Presto trace'
        it_behaves_like 'a query trace'
        it_behaves_like 'a synchronous query trace'
        it_behaves_like 'a sampled trace'
      end

      context 'given a block parameter' do
        before(:each) { client.query('SELECT 1') { nil } }

        it_behaves_like 'a Presto trace'
        it_behaves_like 'a configurable Presto trace'
        it_behaves_like 'a query trace'
        it_behaves_like 'an asynchronous query trace'
        it_behaves_like 'a sampled trace'
      end
    end

    describe '#kill operation' do
      before(:each) do
        client.kill('a_query_id')
      end

      it_behaves_like 'a Presto trace'
      it_behaves_like 'a configurable Presto trace'
      it_behaves_like 'a sampled trace'

      it 'has a kill resource' do
        expect(span.resource).to eq(Datadog::Contrib::Presto::Ext::SPAN_KILL)
      end

      it 'has a query_id tag' do
        expect(span.get_tag('presto.query.id')).to eq('a_query_id')
      end

      it 'is DB type' do
        expect(span.span_type).to eq('db')
      end
    end

    describe '#run_with_names operation' do
      before(:each) { client.run_with_names('SELECT 1') }

      it_behaves_like 'a Presto trace'
      it_behaves_like 'a configurable Presto trace'
      it_behaves_like 'a sampled trace'

      it 'has a query resource' do
        expect(span.resource).to eq('SELECT 1')
      end

      it 'is SQL type' do
        expect(span.span_type).to eq('sql')
      end
    end
  end
end
