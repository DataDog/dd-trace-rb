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

    context 'when the CPU extension is supported' do
      before do
        allow(Datadog::Profiling::Ext::CPU)
          .to receive(:supported?)
          .and_return(true)
      end

      it { is_expected.to be true }
    end

    context 'when the CPU extension is not supported' do
      before do
        allow(Datadog::Profiling::Ext::CPU)
          .to receive(:supported?)
          .and_return(false)
      end

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
