require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/configuration/resolver'

RSpec.describe Datadog::Tracing::Contrib::Configuration::Resolver do
  subject(:resolver) { described_class.new }

  let(:config) { double('config') }

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(value) }

    let(:value) { 'value' }

    context 'with a matcher' do
      before { resolver.add(added_matcher, config) }

      context 'that matches' do
        let(:added_matcher) { value }

        it { is_expected.to be config }
      end

      context 'that does not match' do
        let(:added_matcher) { :different_value }

        it { is_expected.to be nil }
      end
    end

    context 'without a matcher' do
      it { is_expected.to be nil }
    end

    context 'with two matching matchers' do
      before do
        resolver.add(first_matcher, :first)
        resolver.add(second_matcher, :second)
      end

      let(:first_matcher) { 'value' }
      let(:second_matcher) { 'value' }

      it 'returns the latest added one' do
        is_expected.to eq(:second)
      end
    end
  end

  describe '#add' do
    subject(:add) { resolver.add(matcher, config) }

    let(:matcher) { double('matcher') }

    it { is_expected.to be config }

    it 'stores in the configuration field' do
      add
      expect(resolver.configurations).to eq(matcher => config)
    end
  end

  describe '#get' do
    subject(:get) { resolver.get(matcher) }

    let(:matcher) { double('matcher') }

    before { resolver.add(matcher, config) }

    it { is_expected.to be config }

    context 'with a custom #parse_matcher' do
      let(:parsed_matcher) { double('parsed_matcher') }
      let(:resolver) do
        super().tap do |r|
          expect(r).to receive(:parse_matcher).with(matcher).and_return(parsed_matcher).twice
        end
      end

      it { is_expected.to be config }
    end
  end
end
