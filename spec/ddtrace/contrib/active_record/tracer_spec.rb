require 'spec_helper'
require 'ddtrace'

require_relative 'app'

RSpec.describe 'ActiveRecord instrumentation' do
  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:configuration_options) { { tracer: tracer } }

  before(:each) do
    Datadog.configure do |c|
      c.use :active_record, configuration_options
    end
  end

  it 'calls the instrumentation when is used standalone' do
    Article.count
    spans = tracer.writer.spans
    services = tracer.writer.services

    # expect service and trace is sent
    expect(spans.size).to eq(1)
    expect(services['mysql2']).to eq({'app'=>'active_record', 'app_type'=>'db'})

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

  context 'when service_name' do
    subject(:spans) do
      Article.count
      tracer.writer.spans
    end

    let(:query_span) { spans.first }

    context 'is not set' do
      let(:configuration_options) { super().merge({ service_name: nil }) }
      it { expect(query_span.service).to eq('mysql2') }
    end

    context 'is set' do
      let(:service_name) { 'test_active_record' }
      let(:configuration_options) { super().merge({ service_name: service_name }) }

      it { expect(query_span.service).to eq(service_name) }
    end
  end
end
