require 'spec_helper'
require 'ddtrace'

require_relative 'app'

RSpec.describe 'ActiveRecord instrumentation' do
  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:configuration_options) { { tracer: tracer } }

  subject(:spans) do
    Article.count
    tracer.writer.spans
  end

  before(:each) do
    # Prevent extra spans during tests
    Article.count

    # Reset options (that might linger from other tests)
    Datadog.configuration[:active_record].reset_options!

    Datadog.configure do |c|
      c.use :active_record, configuration_options
    end
  end

  after(:each) do
    Datadog.configuration[:active_record].reset_options!
  end

  it 'calls the instrumentation when is used standalone' do
    expect(spans.size).to eq(1)

    services = tracer.writer.services

    # expect service and trace is sent
    expect(services['mysql2']).to eq('app' => 'active_record', 'app_type' => 'db')

    span = spans[0]
    expect(span.service).to eq('mysql2')
    expect(span.name).to eq('mysql2.query')
    expect(span.span_type).to eq('sql')
    expect(span.resource.strip).to eq('SELECT COUNT(*) FROM `articles`')
    expect(span.get_tag('active_record.db.vendor')).to eq('mysql2')
    expect(span.get_tag('active_record.db.name')).to eq('mysql')
    expect(span.get_tag('active_record.db.cached')).to eq(nil)
    expect(span.get_tag('out.host')).to eq(ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'))
    expect(span.get_tag('out.port')).to eq(ENV.fetch('TEST_MYSQL_PORT', 3306).to_s)
    expect(span.get_tag('sql.query')).to eq(nil)
  end

  context 'when tracing only sql events' do
    let(:configuration_options) { { tracer: tracer, trace_events: [:sql] } }

    before(:each) do
      Datadog.configure do |c|
        c.use :active_record, configuration_options
      end
    end

    let(:query_span) { spans.first }

    it 'successfully traces active record' do
      expect(spans.size).to eq(1)

      services = tracer.writer.services

      # expect service and trace is sent
      expect(services['mysql2']).to eq('app' => 'active_record', 'app_type' => 'db')

      span = spans[0]
      expect(span.service).to eq('mysql2')
      expect(span.name).to eq('mysql2.query')
      expect(span.span_type).to eq('sql')
      expect(span.resource.strip).to eq('SELECT COUNT(*) FROM `articles`')
      expect(span.get_tag('active_record.db.vendor')).to eq('mysql2')
      expect(span.get_tag('active_record.db.name')).to eq('mysql')
      expect(span.get_tag('active_record.db.cached')).to eq(nil)
      expect(span.get_tag('out.host')).to eq('127.0.0.1')
      expect(span.get_tag('out.port')).to eq('53306')
      expect(span.get_tag('sql.query')).to eq(nil)
    end
  end




  context 'when service_name' do
    let(:query_span) { spans.first }

    context 'is not set' do
      let(:configuration_options) { super().merge(service_name: nil) }
      it { expect(query_span.service).to eq('mysql2') }
    end

    context 'is set' do
      let(:service_name) { 'test_active_record' }
      let(:configuration_options) { super().merge(service_name: service_name) }

      it { expect(query_span.service).to eq(service_name) }
    end
  end
end
