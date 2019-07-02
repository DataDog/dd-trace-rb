require 'spec_helper'

require 'ddtrace'
require 'presto-client'

RSpec.describe 'Presto::Client instrumentation' do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

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
  let(:host) { ENV.fetch('TEST_PRESTO_HOST', 'localhost') }
  let(:port) { ENV.fetch('TEST_PRESTO_PORT', 8080) }
  let(:user) { 'test_user' }
  let(:schema) { 'test_schema' }
  let(:catalog) { 'memory' }
  let(:time_zone) { 'US/Pacific' }
  let(:language) { 'English' }
  let(:http_proxy) { 'proxy.example.com:8080' }
  let(:model_version) { '0.205' }

  let(:spans) { tracer.writer.spans(:keep) }
  let(:span) { spans.first }

  let(:presto_client_gem_version) { Gem.loaded_specs['presto-client'].version }

  def discard_spans!
    tracer.writer.spans
  end

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
    end
  end

  context 'when the client is configured' do
    context 'with a different service name' do
      let(:service) { 'presto-primary' }
      let(:configuration_options) { { tracer: tracer, service_name: service } }

      it 'produces spans with the correct service' do
        client.run('SELECT 1')
        expect(span.service).to eq(service)
      end
    end

    context 'when the tracer is disabled' do
      before(:each) { tracer.enabled = false }

      it 'does not produce spans' do
        client.run('SELECT 1')
        expect(spans).to be_empty
      end
    end
  end

  describe 'tracing' do
    shared_examples_for 'a Presto trace' do
      it 'has basic properties' do
        expect(spans).to have(1).items
        expect(span.service).to eq('presto')
        expect(span.span_type).to eq('sql')
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

    describe '#run operation' do
      before(:each) { client.run('SELECT 1') }

      it_behaves_like 'a Presto trace'

      it 'has a query resource'  do
        expect(span.resource).to eq(Datadog::Contrib::Presto::Ext::SPAN_QUERY)
      end
    end

    describe '#query opertaion' do
      before(:each) { client.query('SELECT 1') { nil } }

      it_behaves_like 'a Presto trace'

      it 'has a query resource' do
        expect(span.resource).to eq(Datadog::Contrib::Presto::Ext::SPAN_QUERY)
      end
    end

    describe '#kill operation' do
      before(:each) do
        q = client.query('SELECT 1')
        discard_spans!
        client.kill(q)
      end

      it_behaves_like 'a Presto trace'

      it 'has a kill resource' do
        expect(span.resource).to eq(Datadog::Contrib::Presto::Ext::SPAN_KILL)
      end
    end

    describe '#run_with_names operation' do
      before(:each) { client.run_with_names('SELECT 1') }

      it_behaves_like 'a Presto trace'

      it 'has a query resource' do
        expect(span.resource).to eq(Datadog::Contrib::Presto::Ext::SPAN_QUERY)
      end
    end
  end
end
