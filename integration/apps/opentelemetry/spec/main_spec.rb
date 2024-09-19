RSpec.describe 'Main' do
  it 'performs a sanity check' do
    expect { require_relative '../app/main' }.to_not raise_error
  end
end
