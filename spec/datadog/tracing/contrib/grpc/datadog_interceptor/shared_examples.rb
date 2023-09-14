RSpec.shared_examples_for 'it handles the error' do |expected_error|
  it do
    expect { request_response }.to raise_error('test error')

    expect(span).to_not have_error
    expect(span.get_tag('custom.handler')).to eq(expected_error)
    expect(span.get_tag('rpc.system')).to eq('grpc')
    expect(span.get_tag('span.kind')).to eq(span_kind)
  end
end
