# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/tie'

RSpec.describe Datadog::Core::Remote::Tie do
  before { described_class.send(:reset_for_tests!) }

  describe '.boot' do
    context 'when remote configuration is not active' do
      before { allow(Datadog::Core::Remote).to receive(:active_remote).and_return(nil) }

      it 'returns nil' do
        expect(described_class.boot).to be_nil
      end
    end

    context 'when remote configuration is active' do
      let(:remote) { instance_double(Datadog::Core::Remote::Component) }

      before do
        allow(Datadog::Core::Remote).to receive(:active_remote).and_return(remote)
        allow(remote).to receive(:barrier).with(:once).and_return(:lift)
      end

      it 'calls barrier(:once) on the active remote' do
        described_class.boot
        expect(remote).to have_received(:barrier).with(:once).once
      end

      it 'returns a Boot struct with the barrier result and elapsed time' do
        result = described_class.boot
        expect(result).to be_a(Datadog::Core::Remote::Tie::Boot)
        expect(result.barrier).to eq(:lift)
        expect(result.time).to be_a(Numeric)
      end

      it 'is idempotent across many calls in the same process' do
        10.times { described_class.boot }
        expect(remote).to have_received(:barrier).with(:once).once
      end

      it 'reboots after the process pid changes (simulating fork)' do
        described_class.boot

        # Simulate having forked: bump Process.pid for the duration of the call
        new_pid = Process.pid + 1
        allow(Process).to receive(:pid).and_return(new_pid)

        described_class.boot
        expect(remote).to have_received(:barrier).with(:once).twice
      end
    end
  end
end
