require_relative '../app/fibonacci'

# Test some library functions
RSpec.describe '#fib' do
  subject(:call_fib) { fib(n) }
  let(:n) { rand(25..35) }

  it { is_expected.to be_a_kind_of(Integer) }

  context 'given a smaller and larger number' do
    let(:smaller_fib) { fib(n) }
    let(:larger_fib) { fib(n+1) }

    it { expect(larger_fib).to be > smaller_fib }
  end
end
