require 'spec_helper'
require 'ddtrace/profiling'
require 'ddtrace/profiling/ext/cpu'

RSpec.describe Datadog::Profiling::Ext::CPU do
  extend ConfigurationHelpers

  describe '::supported?' do
    subject(:supported?) { described_class.supported? }

    context 'when there is an unsupported_reason' do
      before { allow(described_class).to receive(:unsupported_reason).and_return('Unsupported, sorry :(') }
      it { is_expected.to be false }
    end

    context 'when there is no unsupported_reason' do
      before { allow(described_class).to receive(:unsupported_reason).and_return(nil) }
      it { is_expected.to be true }
    end
  end

  describe '::unsupported_reason' do
    subject(:unsupported_reason) { described_class.unsupported_reason }

    context 'when JRuby is used' do
      before { stub_const('RUBY_ENGINE', 'jruby') }
      it { is_expected.to include 'JRuby' }
    end

    context 'when using MRI Ruby' do
      before { stub_const('RUBY_ENGINE', 'ruby') }

      context 'when running on macOS' do
        before { stub_const('RUBY_PLATFORM', 'x86_64-darwin19') }
        it { is_expected.to include 'macOS' }
      end

      context 'when running on Windows' do
        before { stub_const('RUBY_PLATFORM', 'mswin') }
        it { is_expected.to include 'Windows' }
      end

      context 'when running on a non-Linux platform' do
        before { stub_const('RUBY_PLATFORM', 'my-homegrown-os') }
        it { is_expected.to include 'my-homegrown-os' }
      end

      context 'when running on Linux' do
        before { stub_const('RUBY_PLATFORM', 'x86_64-linux-gnu') }

        context 'when running on MRI < 2.1' do
          before { stub_const('RUBY_VERSION', '2.0.0') }
          it { is_expected.to include 'Ruby >= 2.1' }
        end

        context 'when running on MRI >= 2.1' do
          before { stub_const('RUBY_VERSION', '2.1.0') }

          context 'and \'ffi\'' do
            context 'is not available' do
              include_context 'loaded gems', ffi: nil
              it { is_expected.to include 'Missing ffi' }
            end

            context 'is available' do
              context 'but is below the minimum version' do
                include_context 'loaded gems',
                                ffi: decrement_gem_version(described_class::FFI_MINIMUM_VERSION)

                it { is_expected.to include 'ffi >= 1.0' }
              end

              context 'and meeting the minimum version' do
                include_context 'loaded gems',
                                ffi: described_class::FFI_MINIMUM_VERSION

                it { is_expected.to be nil }
              end
            end
          end
        end
      end
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
