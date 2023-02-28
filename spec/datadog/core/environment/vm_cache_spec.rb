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

      context 'on Ruby <= 3.1' do
        before { skip('Test only runs on Ruby <= 3.1') if RUBY_VERSION >= '3.2.0' }

        it { is_expected.to be_a_kind_of(Integer) }
      end

      context 'on Ruby >= 3.2' do
        before { skip('Test only runs on Ruby >= 3.2') if RUBY_VERSION < '3.2.0' }

        it { is_expected.to be nil }
      end
    end

    describe '.global_method_state' do
      subject(:global_method_state) { described_class.global_method_state }

      context 'on Ruby 2.x' do
        before { skip('Test only runs on Ruby 2.x') unless RUBY_VERSION.start_with?('2.') }

        it { is_expected.to be_a_kind_of(Integer) }
      end

      context 'on Ruby >= 3.x' do
        before { skip('Test only runs on Ruby >= 3.x') if RUBY_VERSION.start_with?('2.') }

        it 'has moved to a per-class method cache' do
          is_expected.to be_nil
        end
      end
    end

    describe '.constant_cache_invalidations' do
      subject(:constant_cache_invalidations) { described_class.constant_cache_invalidations }

      context 'on Ruby <= 3.1' do
        before { skip('Test only runs on Ruby <= 3.1') if RUBY_VERSION >= '3.2.0' }

        it { is_expected.to be nil }
      end

      context 'on Ruby >= 3.2' do
        before { skip('Test only runs on Ruby >= 3.2') if RUBY_VERSION < '3.2.0' }

        it { is_expected.to be_a_kind_of(Integer) }
      end
    end

    describe '.constant_cache_misses' do
      subject(:constant_cache_misses) { described_class.constant_cache_misses }

      context 'on Ruby <= 3.1' do
        before { skip('Test only runs on Ruby <= 3.1') if RUBY_VERSION >= '3.2.0' }

        it { is_expected.to be nil }
      end

      context 'on Ruby >= 3.2' do
        before { skip('Test only runs on Ruby >= 3.2') if RUBY_VERSION < '3.2.0' }

        it { is_expected.to be_a_kind_of(Integer) }
      end
    end
  end
end
