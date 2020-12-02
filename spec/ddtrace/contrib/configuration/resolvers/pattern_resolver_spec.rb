require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Resolvers::PatternResolver do
  subject(:resolver) { described_class.new }

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(name) }

    context 'when matching Regexp has been added' do
      let(:name) { 'my-name' }
      let(:pattern) { /name/ }

      before { resolver.add(pattern) }
      it { is_expected.to eq(pattern) }

      context 'then given a name that isn\'t a String but is case equal' do
        let(:name) { URI('http://localhost') }
        let(:pattern) { /#{Regexp.escape('http://localhost')}/ }

        it 'coerces the name to a String' do
          is_expected.to eq(pattern)
        end
      end
    end

    context 'when non-matching Regexp has been added' do
      let(:name) { 'my-name' }
      before { resolver.add(/not_found/) }
      it { is_expected.to be nil }
    end

    context 'when matching Proc has been added' do
      let(:name) { 'my-name' }
      let(:pattern_proc) { proc { |n| n == name } }
      before { resolver.add(pattern_proc) }
      it { is_expected.to eq(pattern_proc) }

      context 'then given a name that isn\'t a String but is case equal' do
        let(:name) { URI('http://localhost') }
        let(:pattern_proc) { proc { |uri| uri.is_a?(URI) } }

        it 'does not coerce the name' do
          is_expected.to eq(pattern_proc)
        end
      end
    end

    context 'when non-matching Proc has been added' do
      let(:name) { 'my-name' }
      before { resolver.add(proc { |n| n == 'not_found' }) }
      it { is_expected.to be nil }
    end

    context 'when a matching String has been added' do
      let(:name) { 'my-name' }
      let(:pattern) { name }

      before { resolver.add(pattern) }
      it { is_expected.to eq(pattern) }

      context 'then given a name that isn\'t a String but is case equal' do
        let(:name) { URI('http://localhost') }
        let(:pattern) { name.to_s }

        it 'coerces the name to a String' do
          is_expected.to eq(pattern)
        end
      end
    end

    context 'when a non-matching String has been added' do
      let(:name) { 'name' }
      before { resolver.add('my-name') }
      it { is_expected.to be nil }
    end
  end

  describe '#add' do
    subject(:add) { resolver.add(pattern) }

    context 'when given a Regexp' do
      let(:pattern) { /name/ }

      it 'allows any string matching the pattern to resolve' do
        expect { add }.to change { resolver.resolve('my-name') }
          .from(nil)
          .to(pattern)
      end
    end

    context 'when given a Proc' do
      let(:pattern) { proc { |n| n == 'my-name' } }

      it 'allows any string matching the pattern to resolve' do
        expect { add }.to change { resolver.resolve('my-name') }
          .from(nil)
          .to(pattern)
      end
    end

    context 'when given a string' do
      let(:pattern) { 'my-name' }

      it 'allows identical strings to resolve' do
        expect { add }.to change { resolver.resolve(pattern) }
          .from(nil)
          .to(pattern)
      end
    end

    context 'when given some object that responds to #to_s' do
      let(:pattern) { URI('http://localhost') }

      it 'allows its #to_s value to match identical strings when resolved' do
        expect(pattern).to respond_to(:to_s)
        expect { add }.to change { resolver.resolve('http://localhost') }
          .from(nil)
          .to('http://localhost')
      end
    end
  end
end
