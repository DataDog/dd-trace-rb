# typed: false

require 'spec_helper'
require 'datadog/core/environment/host'

RSpec.describe Datadog::Core::Environment::Host do
  describe '::hostname' do
    subject(:hostname) { described_class.hostname }

    if Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2'
      it { is_expected.to be_a_kind_of(String) }
      it { is_expected.to eql(`uname -n`.strip) }
    else
      it { is_expected.to be_nil }
    end
  end

  describe '::kernel_name' do
    subject(:kernel_name) { described_class.kernel_name }
    it { is_expected.to be_a_kind_of(String) }
    it { is_expected.to eql(`uname -s`.strip) }
  end

  describe '::kernel_release' do
    subject(:kernel_release) { described_class.kernel_release }

    if Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2'
      it { is_expected.to be_a_kind_of(String) }
      it { is_expected.to eql(`uname -r`.strip) }
    else
      it { is_expected.to be_nil }
    end
  end

  describe '::kernel_version' do
    subject(:kernel_version) { described_class.kernel_version }

    if Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2'
      it { is_expected.to be_a_kind_of(String) }
      it { is_expected.to eql(`uname -v`.strip) }
    else
      it { is_expected.to be_nil }
    end
  end
end
