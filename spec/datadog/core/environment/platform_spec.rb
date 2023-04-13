require 'spec_helper'
require 'datadog/core/environment/platform'

RSpec.describe Datadog::Core::Environment::Platform do
  describe '::hostname' do
    subject(:hostname) { described_class.hostname }

    context 'when Ruby version < 2.2', if: Datadog::Core::Environment::Ext::LANG_VERSION < '2.2' do
      it { is_expected.to be_nil }
    end

    context 'when Ruby version >= 2.2', if: Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' do
      it { is_expected.to be_a_kind_of(String) }
      it { is_expected.to eql(`uname -n`.strip) }
    end
  end

  describe '::kernel_name' do
    subject(:kernel_name) { described_class.kernel_name }
    it { is_expected.to be_a_kind_of(String) }
    it { is_expected.to eql(`uname -s`.strip) }
  end

  describe '::kernel_release' do
    subject(:kernel_release) { described_class.kernel_release }

    context 'when Ruby version < 2.2', if: Datadog::Core::Environment::Ext::LANG_VERSION < '2.2' do
      it { is_expected.to be_nil }
    end

    context 'when Ruby version >= 2.2', if: Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' do
      it { is_expected.to be_a_kind_of(String) }
      it { is_expected.to eql(`uname -r`.strip) }
    end
  end

  describe '::kernel_version' do
    subject(:kernel_version) { described_class.kernel_version }

    context 'when using JRuby', if: Datadog::Core::Environment::Ext::RUBY_ENGINE == 'jruby' do
      it { is_expected.to be_nil }
    end

    context 'when not using JRuby', unless: Datadog::Core::Environment::Ext::RUBY_ENGINE == 'jruby' do
      context 'when Ruby version < 2.2', if: Datadog::Core::Environment::Ext::LANG_VERSION < '2.2' do
        it { is_expected.to be_nil }
      end

      context 'when Ruby version >= 2.2', if: Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' do
        it { is_expected.to be_a_kind_of(String) }
        it { is_expected.to eql(`uname -v`.strip) }
      end
    end
  end
end
