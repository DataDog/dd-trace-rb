require 'spec_helper'
require 'ddtrace/profiling'

RSpec.describe Datadog::Profiling do
  extend ConfigurationHelpers

  describe '::supported?' do
    subject(:supported?) { described_class.supported? }
    let(:google_protobuf_supported) { double('google-protobuf supported') }

    before do
      allow(described_class)
        .to receive(:google_protobuf_supported?)
        .and_return(google_protobuf_supported)
    end

    it { is_expected.to be(google_protobuf_supported) }
  end

  describe 'native_cpu_time_supported?' do
    subject(:native_cpu_time_supported?) { described_class.native_cpu_time_supported? }

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

  describe '::google_protobuf_supported?' do
    subject(:google_protobuf_supported?) { described_class.google_protobuf_supported? }

    context 'when MRI Ruby is used' do
      before { stub_const('RUBY_PLATFORM', 'x86_64-linux') }

      context 'and \'google-protobuf\'' do
        context 'is not available' do
          include_context 'loaded gems', :'google-protobuf' => nil
          it { is_expected.to be false }
        end

        context 'is available' do
          context 'and meeting the minimum version' do
            include_context 'loaded gems',
                            :'google-protobuf' => described_class::GOOGLE_PROTOBUF_MINIMUM_VERSION

            it { is_expected.to be true }
          end

          context 'but is below the minimum version' do
            include_context 'loaded gems',
                            :'google-protobuf' => decrement_gem_version(described_class::GOOGLE_PROTOBUF_MINIMUM_VERSION)

            it { is_expected.to be false }
          end
        end
      end
    end

    context 'when JRuby is used' do
      before { stub_const('RUBY_PLATFORM', 'java') }
      it { is_expected.to be false }
    end
  end
end
