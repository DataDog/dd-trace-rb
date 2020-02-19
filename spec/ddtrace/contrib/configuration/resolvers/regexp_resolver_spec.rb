require 'spec_helper'
require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Resolvers::RegexpResolver do
  subject(:resolver) { described_class.new }

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(name) }

    context 'when matching pattern has been added' do
      let(:name) { 'my-name' }
      before { resolver.add(/name/) }
      it { is_expected.to eq(/name/) }
    end

    context 'when no matching pattern has been added' do
      let(:name) { 'not_found' }
      it { is_expected.to be :default }
    end

    context 'when a matching string has been added' do
      let(:name) { 'my-name' }
      before { resolver.add(name) }
      it { is_expected.to eq(name) }
    end

    context 'when a non-matching string has been added' do
      let(:name) { 'name' }
      before { resolver.add('my-name') }
      it { is_expected.to be :default }
    end
  end

  describe '#add' do
    subject(:add) { resolver.add(pattern) }

    context 'when given a Regexp' do
      let(:pattern) { /name/ }

      it 'allows any string matching the pattern to resolve' do
        expect { add }.to change { resolver.resolve('my-name') }
          .from(:default)
          .to(pattern)
      end
    end

    context 'when given a string' do
      let(:pattern) { 'my-name' }

      it 'allows identical strings to resolve' do
        expect { add }.to change { resolver.resolve(pattern) }
          .from(:default)
          .to(pattern)
      end
    end

    context 'when given some object that responds to #to_s' do
      let(:pattern) { URI('http://localhost') }

      it 'allows its #to_s value to match identical strings when resolved' do
        expect(pattern).to respond_to(:to_s)
        expect { add }.to change { resolver.resolve('http://localhost') }
          .from(:default)
          .to('http://localhost')
      end
    end
  end
end
