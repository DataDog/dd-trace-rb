RSpec.shared_examples 'a resolver with a matching pattern' do
  it 'returns the associated configuration' do
    is_expected.to be(config)
  end
end
