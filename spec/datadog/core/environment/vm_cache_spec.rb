# typed: false

require 'spec_helper'
require 'datadog/core/environment/vm_cache'

RSpec.describe Datadog::Core::Environment::VMCache do
  describe '.available?' do
    subject(:available?) { described_class.available? }

    context 'with CRuby', if: PlatformHelpers.mri? do
      it { is_expected.to be_truthy }
    end

    context 'with non-CRuby', unless: PlatformHelpers.mri? do
      it { is_expected.to be_falsey }
    end
  end

  context 'with CRuby' do
    before { skip('This feature is only supported in CRuby') unless PlatformHelpers.mri? }

    describe '.global_constant_state' do
      subject(:global_constant_state) { described_class.global_constant_state }

      it { is_expected.to be_a_kind_of(Integer) }
    end

    describe '.global_method_state' do
      subject(:global_method_state) { described_class.global_method_state }

      context 'with Ruby < 3', if: RUBY_VERSION < '3.0.0' do
        it { is_expected.to be_a_kind_of(Integer) }
      end

      context 'with Ruby >= 3', if: RUBY_VERSION >= '3.0.0' do
        it 'has moved to a per-class method cache' do
          is_expected.to be_nil
        end
      end
    end
  end
end
