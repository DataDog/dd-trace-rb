RSpec.shared_context 'a resolver with a matching pattern' do
  it 'returns the associated configuration' do
    is_expected.to be(config)
  end
end
