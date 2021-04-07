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

  describe '::google_protobuf_supported?' do
    subject(:google_protobuf_supported?) { described_class.google_protobuf_supported? }

    before do
      # Ignore any actual loading failures in the local environment
      if described_class.instance_variable_defined?(:@failed_to_load_protobuf)
        described_class.remove_instance_variable(:@failed_to_load_protobuf)
      end
    end

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
