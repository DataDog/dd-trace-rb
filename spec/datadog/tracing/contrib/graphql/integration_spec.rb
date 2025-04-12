require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/graphql/integration'

RSpec.describe Datadog::Tracing::Contrib::GraphQL::Integration do
  let(:integration) { described_class.new(:graphql) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "graphql" gem is loaded' do
      include_context 'loaded gems', graphql: '2.2.6'
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "graphql" gem is not loaded' do
      include_context 'loaded gems', graphql: nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when GraphQL is not defined' do
      before do
        hide_const('GraphQL')
      end

      it { is_expected.to be false }
    end

    context 'when GraphQL is defined' do
      before do
        stub_const('GraphQL', Class.new)
      end

      it { is_expected.to be true }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }
    context 'when "graphql" gem is loaded with a version' do
      backport_support = {
        '1.13.21' => '2.0',
        '2.0.28' => '2.1',
        '2.1.11' => '2.2',
      }

      backport_support.each do |backported_version, broken_version|
        context "when #{backported_version}" do
          include_context 'loaded gems', graphql: backported_version
          it { is_expected.to be true }
        end

        context "when #{decrement_gem_version(backported_version)}" do
          include_context 'loaded gems', graphql: decrement_gem_version(backported_version)
          it { is_expected.to be false }
        end

        context "when #{broken_version}" do
          include_context 'loaded gems', graphql: broken_version
          it { is_expected.to be false }
        end
      end

      context "when #{decrement_gem_version('2.2.6')}" do
        include_context 'loaded gems', graphql: decrement_gem_version('2.2.6')
        it { is_expected.to be false }
      end

      context 'when 2.2.6' do
        include_context 'loaded gems', graphql: '2.2.6'
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', graphql: nil
      it { is_expected.to be false }
    end
  end

  describe '#auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    it { is_expected.to be(true) }
  end

  describe '.trace_supported?' do
    subject(:trace_supported) { described_class.trace_supported? }

    context 'with version `2.0.19`' do
      include_context 'loaded gems', graphql: '2.0.19'
      it { is_expected.to be true }
    end

    context 'with version `2.0.18`' do
      include_context 'loaded gems', graphql: decrement_gem_version('2.0.19')
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::GraphQL::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }

    it { is_expected.to be Datadog::Tracing::Contrib::GraphQL::Patcher }
  end

  it_behaves_like 'a contrib integration'
end