# encoding: utf-8

require 'spec_helper'
require 'ddtrace/runtime/identity'

RSpec.describe Datadog::Runtime::Identity do
  describe '::id' do
    subject(:id) { described_class.id }

    it { is_expected.to be_a_kind_of(String) }

    context 'when invoked twice' do
      it { expect(described_class.id).to eq(described_class.id) }
    end

    context 'when invoked around a fork' do
      before { skip unless PlatformHelpers.supports_fork? }

      let(:before_fork_id) { described_class.id }
      let(:inside_fork_id) { described_class.id }
      let(:after_fork_id) { described_class.id }

      it do
        # Check before forking
        expect(before_fork_id).to be_a_kind_of(String)

        # Invoke in fork, make sure expectations run before continuing.
        expect_in_fork do
          expect(inside_fork_id).to be_a_kind_of(String)
          expect(inside_fork_id).to_not eq(before_fork_id)
        end

        # Check after forking
        expect(after_fork_id).to eq(before_fork_id)
      end
    end
  end

  describe '::lang' do
    subject(:lang) { described_class.lang }
    it { is_expected.to eq(Datadog::Ext::Runtime::LANG) }
  end

  describe '::lang_engine' do
    subject(:lang_engine) { described_class.lang_engine }
    it { is_expected.to eq(Datadog::Ext::Runtime::LANG_ENGINE) }
  end

  describe '::lang_interpreter' do
    subject(:lang_interpreter) { described_class.lang_interpreter }
    it { is_expected.to eq(Datadog::Ext::Runtime::LANG_INTERPRETER) }
  end

  describe '::lang_platform' do
    subject(:lang_platform) { described_class.lang_platform }
    it { is_expected.to eq(Datadog::Ext::Runtime::LANG_PLATFORM) }
  end

  describe '::lang_version' do
    subject(:lang_version) { described_class.lang_version }
    it { is_expected.to eq(Datadog::Ext::Runtime::LANG_VERSION) }
  end

  describe '::tracer_version' do
    subject(:tracer_version) { described_class.tracer_version }
    it { is_expected.to eq(Datadog::Ext::Runtime::TRACER_VERSION) }
  end
end
