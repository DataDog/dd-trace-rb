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

      context 'and \'google-protobuf\'' do
        context 'is not available' do
          include_context 'loaded gems', 'google-protobuf': nil

          it { is_expected.to include 'Missing google-protobuf' }
        end

        context 'is available' do
          context 'but is below the minimum version' do
            include_context 'loaded gems', 'google-protobuf': Gem::Version.new('2.9')

            it { is_expected.to include 'google-protobuf >= 3.0' }
          end

          context 'and meeting the minimum version' do
            include_context 'loaded gems', 'google-protobuf': Gem::Version.new('3.0')

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
      end
    end
  end

  describe '::protobuf_loaded_successfully?' do
    subject(:protobuf_loaded_successfully?) { described_class.protobuf_loaded_successfully? }

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
        expect(Kernel).to receive(:warn).with(/Error while loading/)

        protobuf_loaded_successfully?
      end
    end

    context 'when requiring protobuf is successful' do
      before { allow(described_class).to receive(:require).and_return(true) }

      it { is_expected.to be true }
    end
  end
end
