require 'spec_helper'
require 'ddtrace'

require_relative 'app'

RSpec.describe 'Dalli instrumentation' do
  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }

  before(:each) do
    Datadog.configure do |c|
      c.use :active_record, tracer: tracer
    end
  end

  it 'calls the instrumentation when is used standalone' do
    Article.count
    spans = tracer.writer.spans
    expect(spans.size).to eq(1)

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
