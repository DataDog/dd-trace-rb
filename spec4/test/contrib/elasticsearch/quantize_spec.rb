require('contrib/elasticsearch/test_helper')
require('ddtrace')
require('helper')
require('ddtrace/contrib/elasticsearch/quantize')
require('spec_helper')

RSpec.describe Datadog::Contrib::Elasticsearch::Quantize do
  it('id') do
    expect(described_class.format_url('/my/thing/1')).to(eq('/my/thing/?'))
    expect(described_class.format_url('/my/thing/1/')).to(eq('/my/thing/?/'))
    expect(described_class.format_url('/my/thing/1/is/cool')).to(eq('/my/thing/?/is/cool'))
    expect(described_class.format_url('/my/thing/1?is=cool')).to(eq('/my/thing/??is=cool'))
    expect(described_class.format_url('/my/thing/1two3/z')).to(eq('/my/thing/?/z'))
    expect(described_class.format_url('/my/thing/1two3/z/')).to(eq('/my/thing/?/z/'))
    expect(described_class.format_url('/my/thing/1two3/z?a=b')).to(eq('/my/thing/?/z?a=b'))
    expect(described_class.format_url('/my/thing/1two3/z?a=b123')).to(eq('/my/thing/?/z?a=b?'))
    expect(described_class.format_url('/my/thing/1two3/abc')).to(eq('/my/thing/?/abc'))
    expect(described_class.format_url('/my/thing/1two3/abc/')).to(eq('/my/thing/?/abc/'))
    expect(described_class.format_url('/my/thing231/1two3/abc/')).to(eq('/my/thing?/?/abc/'))
    expect(described_class.format_url('/my/thing/1447990c-811a-4a83-b7e2-c3e8a4a6ff54/_termvector'))
      .to(eq('/my/thing/?/_termvector'))
    expect(described_class.format_url('app_prod/user/1fff2c9dc2f3e/_termvector'))
      .to(eq('app_prod/user/?/_termvector'))
  end

  it('index') do
    expect(described_class.format_url('/my123456/thing')).to(eq('/my?/thing'))
    expect(described_class.format_url('/my123456more/thing')).to(eq('/my?more/thing'))
    expect(described_class.format_url('/my123456and789/thing')).to(eq('/my?and?/thing'))
  end

  it('combine') do
    expect(described_class.format_url('/my123/thing/456789')).to(eq('/my?/thing/?'))
  end

  it('body') do
    body = '{"ids":["1","2","3"]}'
    quantized_body = '{"ids":["?"]}'
    expect(described_class.format_body(body)).to(eq(quantized_body))
    body = '{"query":{"match":{"title":"test"}}}'
    quantized_body = '{"query":{"match":{"title":"?"}}}'
    # rubocop:disable Metrics/LineLength
    expect(described_class.format_body(body)).to(eq(quantized_body))
    body = "{}\n{\"query\":{\"match_all\":{}}}\n{\"index\":\"myindex\",\"type\":\"mytype\"}\n{\"query\":{\"query_string\":{\"query\":\"\\\"test\\\"\"}}}\n{\"search_type\":\"count\"}\n{\"aggregations\":{\"published\":{\"terms\":{\"field\":\"published\"}}}}\n"
    quantized_body = "{}\n{\"query\":{\"match_all\":{}}}\n{\"index\":\"?\",\"type\":\"?\"}\n{\"query\":{\"query_string\":{\"query\":\"?\"}}}\n{\"search_type\":\"?\"}\n{\"aggregations\":{\"published\":{\"terms\":{\"field\":\"?\"}}}}"
    expect(described_class.format_body(body)).to(eq(quantized_body))
    body = "{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":1}}\n{\"title\":\"foo\"}\n{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":2}}\n{\"title\":\"foo\"}\n"
    quantized_body = "{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":1}}\n{\"title\":\"?\"}\n{\"index\":{\"_index\":\"myindex\",\"_type\":\"mytype\",\"_id\":2}}\n{\"title\":\"?\"}"
    # rubocop:enable Metrics/LineLength
    expect(described_class.format_body(body)).to(eq(quantized_body))
  end

  it('body show') do
    body = '{"query":{"match":{"title":"test","subtitle":"test"}}}'
    quantized_body = '{"query":{"match":{"title":"test","subtitle":"?"}}}'
    expect(described_class.format_body(body, show: [:title])).to(eq(quantized_body))
    body = '{"query":{"match":{"title":"test","subtitle":"test"}}}'
    quantized_body = '{"query":{"match":{"title":"test","subtitle":"test"}}}'
    expect(described_class.format_body(body, show: :all)).to(eq(quantized_body))
    body = '[{"foo":"foo"},{"bar":"bar"}]'
    quantized_body = '[{"foo":"foo"},{"bar":"bar"}]'
    expect(described_class.format_body(body, show: :all)).to(eq(quantized_body))
    body = '["foo","bar"]'
    quantized_body = '["foo","bar"]'
    expect(described_class.format_body(body, show: :all)).to(eq(quantized_body))
  end

  it('body exclude') do
    body = '{"query":{"match":{"title":"test","subtitle":"test"}}}'
    quantized_body = '{"query":{"match":{"subtitle":"?"}}}'
    expect(described_class.format_body(body, exclude: [:title])).to(eq(quantized_body))
  end
end
