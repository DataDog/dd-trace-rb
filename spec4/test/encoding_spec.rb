require('spec_helper')
require('ddtrace/span')
require('ddtrace/encoding')
RSpec.describe Datadog::Encoding::JSONEncoder do
  it('traces encoding json') do
    encoder = described_class.new
    traces = get_test_traces(2)
    to_send = encoder.encode_traces(traces)
    expect(to_send.is_a?(String)).to(eq(true))
    items = JSON.parse(to_send)
    expect(2).to(eq(items.length))
    expect(2).to(eq(items[0].length))
    expect(2).to(eq(items[1].length))
    span = items[0][0]
    expect(span['span_id']).to(be_truthy)
    expect(span['parent_id']).to(be_truthy)
    expect(span['trace_id']).to(be_truthy)
    expect(span['name']).to(be_truthy)
    expect(span['service']).to(be_truthy)
    expect(span['resource']).to(be_truthy)
    expect(span['type']).to(be_truthy)
    expect(span['meta']).to(be_truthy)
    expect(span['error']).to(be_truthy)
    expect(span['start']).to(be_truthy)
    expect(span['duration']).to(be_truthy)
  end
end
