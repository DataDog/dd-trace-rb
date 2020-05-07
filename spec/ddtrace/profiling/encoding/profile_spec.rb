require 'spec_helper'

require 'ddtrace/profiling/encoding/profile'
require 'ddtrace/profiling/events/stack'

RSpec.describe Datadog::Profiling::Encoding::Profile::Protobuf do
  describe '::encode' do
    subject(:encode) { described_class.encode(events) }

    let(:builder) { instance_double(Datadog::Profiling::Pprof::Builder) }
    let(:profile) { instance_double(Perftools::Profiles::Profile) }
    let(:encoded_profile) { double('encoded profile') }

    before do
      expect(Datadog::Profiling::Pprof::Builder)
        .to receive(:new)
        .with(events)
        .and_return(builder)

      expect(builder)
        .to receive(:to_profile)
        .and_return(profile)

      expect(Perftools::Profiles::Profile)
        .to receive(:encode)
        .with(profile)
        .and_return(encoded_profile)
    end

    context 'given StackSample events' do
      # Inherit and build, because the encoder type checks the events passed.
      # It's expensive to build a StackSample manually, and verifying doubles don't pass.
      def build_stack_sample
        @stack_sample_class ||= Class.new(Datadog::Profiling::Events::StackSample) do
          def initialize; end
        end

        @stack_sample_class.new
      end

      let(:events) { Array.new(2) { build_stack_sample } }

      it { is_expected.to be encoded_profile }
    end
  end
end
