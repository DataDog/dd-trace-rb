require 'spec_helper'
require 'ddtrace/profiling'
require 'ddtrace/profiling/ext/cpu'

RSpec.describe Datadog::Profiling::Ext::CPU do
  extend ConfigurationHelpers

  describe '::supported?' do
    subject(:supported?) { described_class.supported? }

    context 'when MRI Ruby is used' do
      before { stub_const('RUBY_PLATFORM', 'x86_64-linux') }

      context 'of version < 2.1' do
        before { stub_const('RUBY_VERSION', '2.0') }
        it { is_expected.to be false }
      end

      context 'of version >= 2.1' do
        before { stub_const('RUBY_VERSION', '2.1') }

        context 'and \'ffi\'' do
          context 'is not available' do
            include_context 'loaded gems', ffi: nil
            it { is_expected.to be false }
          end

          context 'is available' do
            context 'and meeting the minimum version' do
              include_context 'loaded gems',
                              ffi: described_class::FFI_MINIMUM_VERSION

              it { is_expected.to be true }
            end

            context 'but is below the minimum version' do
              include_context 'loaded gems',
                              ffi: decrement_gem_version(described_class::FFI_MINIMUM_VERSION)

              it { is_expected.to be false }
            end
          end
        end
      end
    end

    context 'when JRuby is used' do
      before { stub_const('RUBY_PLATFORM', 'java') }
      it { is_expected.to be false }
    end
  end

  describe '::apply!' do
    subject(:apply!) { described_class.apply! }

    before { stub_const('Thread', ::Thread.dup) }

    context 'when native CPU time is supported' do
      before { skip 'CPU profiling not supported' unless described_class.supported? }

      it 'adds Thread extensions' do
        apply!
        expect(Thread.ancestors).to include(Datadog::Profiling::Ext::CThread)
      end
    end

    context 'when native CPU time is not supported' do
      before do
        allow(described_class)
          .to receive(:supported?)
          .and_return(false)
      end

      it 'skips adding Thread extensions' do
        is_expected.to be false
      end
    end
  end
end
