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

      context 'on Ruby < 3.2' do
        before { skip('Test only runs on Ruby < 3.2') unless RubyVersion.is?('< 3.2') }

        it { is_expected.to be_a_kind_of(Integer) }
      end

      context 'on Ruby >= 3.2' do
        before { skip('Test only runs on Ruby >= 3.2') unless RubyVersion.is?('>= 3.2') }

        it { is_expected.to be nil }
      end
    end

    describe '.global_method_state' do
      subject(:global_method_state) { described_class.global_method_state }

      context 'on Ruby 2' do
        before { skip('Test only runs on Ruby 2') unless RubyVersion.is?('< 3') }

        it { is_expected.to be_a_kind_of(Integer) }
      end

      context 'on Ruby 3+' do
        before { skip('Test only runs on Ruby 3+') unless RubyVersion.is?('>= 3') }

        it 'has moved to a per-class method cache' do
          is_expected.to be_nil
        end
      end
    end

    describe '.constant_cache_invalidations' do
      subject(:constant_cache_invalidations) { described_class.constant_cache_invalidations }

      context 'on Ruby < 3.2' do
        before { skip('Test only runs on Ruby < 3.2') unless RubyVersion.is?('< 3.2') }

        it { is_expected.to be nil }
      end

      context 'on Ruby >= 3.2' do
        before { skip('Test only runs on Ruby >= 3.2') unless RubyVersion.is?('>= 3.2') }

        it { is_expected.to be_a_kind_of(Integer) }
      end
    end

    describe '.constant_cache_misses' do
      subject(:constant_cache_misses) { described_class.constant_cache_misses }

      context 'on Ruby < 3.2' do
        before { skip('Test only runs on Ruby < 3.2') unless RubyVersion.is?('< 3.2') }

        it { is_expected.to be nil }
      end

      context 'on Ruby >= 3.2' do
        before { skip('Test only runs on Ruby >= 3.2') unless RubyVersion.is?('>= 3.2') }

        it { is_expected.to be_a_kind_of(Integer) }
      end
    end
  end
end
