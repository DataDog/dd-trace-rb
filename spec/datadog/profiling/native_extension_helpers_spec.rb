# typed: false
require 'ext/ddtrace_profiling_native_extension/native_extension_helpers'

RSpec.describe Datadog::Profiling::NativeExtensionHelpers::Supported do
  describe '.supported?' do
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

  describe '.unsupported_reason' do
    subject(:unsupported_reason) { described_class.unsupported_reason }

    context 'when disabled via the DD_PROFILING_NO_EXTENSION environment variable' do
      around { |example| ClimateControl.modify('DD_PROFILING_NO_EXTENSION' => 'true') { example.run } }

      it { is_expected.to include 'DD_PROFILING_NO_EXTENSION' }
    end

    context 'when JRuby is used' do
      before { stub_const('RUBY_ENGINE', 'jruby') }

      it { is_expected.to include 'JRuby' }
    end

    context 'when TruffleRuby is used' do
      before { stub_const('RUBY_ENGINE', 'truffleruby') }

      it { is_expected.to include 'TruffleRuby' }
    end

    context 'when not on JRuby or TruffleRuby' do
      before { stub_const('RUBY_ENGINE', 'ruby') }

      context 'when on Windows' do
        before { expect(Gem).to receive(:win_platform?).and_return(true) }

        it { is_expected.to include 'Windows' }
      end

      context 'when not on Windows' do
        before { allow(Gem).to receive(:win_platform?).and_return(false) }

        context 'when Ruby CAN NOT use the MJIT header' do
          before { stub_const('Datadog::Profiling::NativeExtensionHelpers::CAN_USE_MJIT_HEADER', false) }

          it { is_expected.to be nil }
        end

        context 'when Ruby CAN use the MJIT header' do
          before { stub_const('Datadog::Profiling::NativeExtensionHelpers::CAN_USE_MJIT_HEADER', true) }

          context 'when Ruby DOES NOT have MJIT support' do
            before { allow(RbConfig::CONFIG).to receive(:[]).with('MJIT_SUPPORT').and_return('no') }

            it { is_expected.to include 'without JIT' }
          end

          context 'when Ruby DOES have MJIT support' do
            before { allow(RbConfig::CONFIG).to receive(:[]).with('MJIT_SUPPORT').and_return('yes') }

            it { is_expected.to be nil }
          end
        end
      end
    end
  end
end
