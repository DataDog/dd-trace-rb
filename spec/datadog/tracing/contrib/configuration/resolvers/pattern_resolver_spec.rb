require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'

RSpec.describe Datadog::Tracing::Contrib::Configuration::Resolvers::PatternResolver do
  subject(:resolver) { described_class.new }

  let(:config) { instance_double('config') }

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(value) }

    context 'when matching Regexp has been added' do
      let(:value) { 'my-value' }
      let(:matcher) { /value/ }

      before { resolver.add(matcher, config) }

      it { is_expected.to eq(config) }

      context 'then given a value that isn\'t a String but is case equal' do
        let(:value) { URI('http://localhost') }
        let(:matcher) { /#{Regexp.escape('http://localhost')}/ }

        it 'coerces the value to a String' do
          is_expected.to eq(config)
        end
      end
    end

    context 'when non-matching Regexp has been added' do
      let(:value) { 'my-value' }

      before { resolver.add(/not_found/, config) }

      it { is_expected.to be nil }
    end

    context 'when matching Proc has been added' do
      let(:value) { 'my-value' }
      let(:matcher_proc) { proc { |n| n == value } }

      before { resolver.add(matcher_proc, config) }

      it { is_expected.to eq(config) }

      context 'then given a value that isn\'t a String but is case equal' do
        let(:value) { URI('http://localhost') }
        let(:matcher_proc) { proc { |uri| uri.is_a?(URI) } }

        it 'does not coerce the value' do
          is_expected.to eq(config)
        end
      end
    end

    context 'when non-matching Proc has been added' do
      let(:value) { 'my-value' }

      before { resolver.add(proc { |n| n == 'not_found' }, config) }

      it { is_expected.to be nil }
    end

    context 'when a matching String has been added' do
      let(:value) { 'my-value' }
      let(:matcher) { value }

      before { resolver.add(matcher, config) }

      it { is_expected.to eq(config) }

      context 'then given a value that isn\'t a String but is case equal' do
        let(:value) { URI('http://localhost') }
        let(:matcher) { value.to_s }

        it 'coerces the value to a String' do
          is_expected.to eq(config)
        end
      end
    end

    context 'when a non-matching String has been added' do
      let(:value) { 'value' }

      before { resolver.add('my-value', config) }

      it { is_expected.to be nil }

      describe 'benchmark' do
        before { skip('Benchmark results not currently captured in CI') if ENV.key?('CI') }

        it 'measure PatternResolver#resolve(str)' do
          require 'benchmark/ips'

          Benchmark.ips do |x|
            x.config(time: 15, warmup: 2)

            x.report 'resolver.resolve(str)' do
              resolver.resolve(value)
            end

            x.compare!
          end
        end
      end
    end

    context 'with two matching patterns' do
      let(:value) { 'value' }

      let(:first_matcher) { 'value' }
      let(:second_matcher) { /value/ }

      let(:first_config) { instance_double('first config') }
      let(:second_config) { instance_double('second config') }

      before do
        resolver.add(first_matcher, first_config)
        resolver.add(second_matcher, second_config)
      end

      it 'returns the latest added one' do
        is_expected.to eq(second_config)
      end
    end
  end

  describe '#add' do
    subject(:add) { resolver.add(matcher, config) }

    context 'when given a Regexp' do
      let(:matcher) { /value/ }

      it 'allows any string matching the matcher to resolve' do
        expect { add }.to change { resolver.resolve('my-value') }
          .from(nil)
          .to(config)
      end
    end

    context 'when given a Proc' do
      let(:matcher) { proc { |n| n == 'my-value' } }

      it 'allows any string matching the matcher to resolve' do
        expect { add }.to change { resolver.resolve('my-value') }
          .from(nil)
          .to(config)
      end
    end

    context 'when given a string' do
      let(:matcher) { 'my-value' }

      it 'allows identical strings to resolve' do
        expect { add }.to change { resolver.resolve(matcher) }
          .from(nil)
          .to(config)
      end
    end

    context 'when given some object that responds to #to_s' do
      let(:matcher) { URI('http://localhost') }

      it 'allows its #to_s value to match identical strings when resolved' do
        expect(matcher).to respond_to(:to_s)
        expect { add }.to change { resolver.resolve('http://localhost') }
          .from(nil)
          .to(config)
      end
    end
  end
end
