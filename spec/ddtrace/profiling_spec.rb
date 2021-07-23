require 'spec_helper'
require 'ddtrace/profiling'

RSpec.describe Datadog::Profiling do
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

    context 'when not using JRuby' do
      before { stub_const('RUBY_ENGINE', 'ruby') }

      context 'when the profiling native library fails to be loaded with a exception' do
        let(:loaderror) do
          begin
            raise LoadError, 'Simulated require failure'
          rescue LoadError => e
            e
          end
        end

        before do
          expect(described_class).to receive(:try_loading_native_library).and_return([false, loaderror])
        end

        it { is_expected.to include 'error loading the profiling native extension' }
      end

      context "when the profiling native library fails to be loaded but there's no exception" do
        before do
          expect(described_class).to receive(:try_loading_native_library).and_return [false, nil]
        end

        it { is_expected.to include 'profiling native extension did not load correctly' }
      end

      context "when the profiling native library is available and 'google-protobuf'" do
        before do
          expect(described_class).to receive(:try_loading_native_library).and_return [true, nil]
        end

        context 'is not available' do
          include_context 'loaded gems', :'google-protobuf' => nil

          before do
            hide_const('::Google::Protobuf')
          end

          it { is_expected.to include 'Missing google-protobuf' }
        end

        context 'is available but not yet loaded' do
          before do
            hide_const('::Google::Protobuf')
          end

          context 'but is below the minimum version' do
            include_context 'loaded gems', :'google-protobuf' => Gem::Version.new('2.9')

            it { is_expected.to include 'google-protobuf >= 3.0' }
          end

          context 'and meeting the minimum version' do
            include_context 'loaded gems', :'google-protobuf' => Gem::Version.new('3.0')

            context 'when protobuf does not load correctly' do
              before { allow(described_class).to receive(:protobuf_loaded_successfully?).and_return(false) }

              it { is_expected.to include 'error loading' }
            end

            context 'when protobuf loads successfully' do
              before { allow(described_class).to receive(:protobuf_loaded_successfully?).and_return(true) }

              it { is_expected.to be nil }
            end
          end
        end

        context 'is already loaded' do
          before do
            stub_const('::Google::Protobuf', Module.new)
            allow(described_class).to receive(:protobuf_loaded_successfully?).and_return(true)
          end

          it { is_expected.to be nil }
        end
      end
    end
  end

  describe '::protobuf_loaded_successfully?' do
    subject(:protobuf_loaded_successfully?) { described_class.send(:protobuf_loaded_successfully?) }

    before do
      # Remove any previous state
      if described_class.instance_variable_defined?(:@protobuf_loaded)
        described_class.remove_instance_variable(:@protobuf_loaded)
      end

      allow(Kernel).to receive(:warn)
    end

    context 'when there is an issue requiring protobuf' do
      before { allow(described_class).to receive(:require).and_raise(LoadError.new('Simulated require failure')) }

      it { is_expected.to be false }

      it 'logs a warning' do
        expect(Kernel).to receive(:warn).with(/Error while loading google-protobuf/)

        protobuf_loaded_successfully?
      end
    end

    context 'when requiring protobuf is successful' do
      before { allow(described_class).to receive(:require).and_return(true) }

      it { is_expected.to be true }
    end
  end

  describe '::try_loading_native_library' do
    subject(:try_loading_native_library) { described_class.send(:try_loading_native_library) }

    let(:native_extension_require) { "ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}" }

    around { |example| ClimateControl.modify('DD_PROFILING_NO_EXTENSION' => nil) { example.run } }

    context 'when the profiling native library loads successfully' do
      before do
        expect(described_class)
          .to receive(:require)
          .with(native_extension_require)
        stub_const('Datadog::Profiling::NativeExtension', double(native_working?: true))
      end

      it { is_expected.to eq [true, nil] }
    end

    context 'when the profiling native library fails to load with a LoadError' do
      before do
        expect(described_class).to receive(:require).with(native_extension_require).and_raise(loaderror)
      end

      let(:loaderror) { LoadError.new('Simulated require failure') }

      it { is_expected.to eq [false, loaderror] }
    end

    context 'when the profiling native library fails to load with a different error' do
      before do
        expect(described_class).to receive(:require).with(native_extension_require).and_raise(error)
      end

      let(:error) { StandardError.new('Simulated require failure') }

      it { is_expected.to eq [false, error] }
    end

    context 'when the profiling native library loads but does not install code correctly' do
      before do
        expect(described_class)
          .to receive(:require)
          .with(native_extension_require)
        stub_const('Datadog::Profiling::NativeExtension', double(native_working?: false))
      end

      it { is_expected.to eq [false, nil] }
    end

    context "when DD_PROFILING_NO_EXTENSION is set to 'true'" do
      before do
        allow(Kernel).to receive(:warn)
        described_class.const_get(:SKIPPED_NATIVE_EXTENSION_ONLY_ONCE).send(:reset_ran_once_state_for_tests)
      end

      around { |example| ClimateControl.modify('DD_PROFILING_NO_EXTENSION' => 'true') { example.run } }

      it { is_expected.to eq [true, nil] }

      it 'logs a warning' do
        expect(Kernel).to receive(:warn).with(/DD_PROFILING_NO_EXTENSION/)

        try_loading_native_library
      end

      it 'does not try to require the native extension' do
        expect(described_class).to_not receive(:require)

        try_loading_native_library
      end

      it 'does not try to call NativeExtension.native_working?' do
        stub_const('Datadog::Profiling::NativeExtension', double('native_extension double which should not be used'))

        try_loading_native_library
      end
    end
  end
end
