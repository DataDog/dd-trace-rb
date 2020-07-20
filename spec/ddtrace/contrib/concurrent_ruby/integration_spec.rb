require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/concurrent_ruby/integration'

RSpec.describe Datadog::Contrib::ConcurrentRuby::Integration do
  extend ConfigurationHelpers

  let(:integration) { described_class.new(:concurrent_ruby) }

  describe '.version' do
    subject(:version) { described_class.version }

    context 'when the "actionpack" gem is loaded' do
      include_context 'loaded gems', :'concurrent-ruby' => described_class::MINIMUM_VERSION
      it { is_expected.to be_a_kind_of(Gem::Version) }
    end

    context 'when "actionpack" gem is not loaded' do
      include_context 'loaded gems', :'concurrent-ruby' => nil
      it { is_expected.to be nil }
    end
  end

  describe '.loaded?' do
    subject(:loaded?) { described_class.loaded? }

    context 'when Concurrent::Future is defined' do
      before { stub_const('Concurrent::Future', Class.new) }
      it { is_expected.to be true }
    end

    context 'when Concurrent::Future is not defined' do
      before { hide_const('Concurrent::Future') }
      it { is_expected.to be false }
    end
  end

  describe '.compatible?' do
    subject(:compatible?) { described_class.compatible? }

    context 'when "actionpack" gem is loaded with a version' do
      context 'that is less than the minimum' do
        include_context 'loaded gems', :'concurrent-ruby' => decrement_gem_version(described_class::MINIMUM_VERSION)
        it { is_expected.to be false }
      end

      context 'that meets the minimum version' do
        include_context 'loaded gems', :'concurrent-ruby' => described_class::MINIMUM_VERSION
        it { is_expected.to be true }
      end
    end

    context 'when gem is not loaded' do
      include_context 'loaded gems', :'concurrent-ruby' => nil
      it { is_expected.to be false }
    end
  end

  describe '#default_configuration' do
    subject(:default_configuration) { integration.default_configuration }
    it { is_expected.to be_a_kind_of(Datadog::Contrib::ConcurrentRuby::Configuration::Settings) }
  end

  describe '#patcher' do
    subject(:patcher) { integration.patcher }
    it { is_expected.to be Datadog::Contrib::ConcurrentRuby::Patcher }
  end
end
