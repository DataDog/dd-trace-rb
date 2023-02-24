RSpec.describe 'Datadog::Kit::EnableCoreDumps' do
  before do
    # Make sure we don't touch the actual real value
    allow(Process).to receive(:setrlimit).with(:CORE, anything).at_least(1).time

    allow(Kernel).to receive(:warn)
    expect(Process).to receive(:getrlimit).with(:CORE).and_return(setrlimit_result).at_least(1).time

    # This should only be required with the mocks enabled, to make sure we don't actually affect the running
    # Ruby instance
    require 'datadog/kit/enable_core_dumps'
  end

  subject(:enable_core_dumps) { Datadog::Kit::EnableCoreDumps.call }

  context 'when core dumps are disabled' do
    let(:setrlimit_result) { [0, 0] }

    it 'does not change anything' do
      expect(Process).to_not receive(:setrlimit)

      enable_core_dumps
    end

    it 'logs a message informing that it could not enable core dumps' do
      expect(Kernel).to receive(:warn).with(/Could not enable core dumps/)

      enable_core_dumps
    end
  end

  context 'when core dumps were already enabled at the maximum size' do
    let(:setrlimit_result) { [1, 1] }

    it 'does not change anything' do
      expect(Process).to_not receive(:setrlimit)

      enable_core_dumps
    end

    it 'logs a message informing core dumps were already enabled' do
      expect(Kernel).to receive(:warn).with(/Core dumps already enabled/)

      enable_core_dumps
    end
  end

  context 'when core dumps can be enabled' do
    context 'when core dumps were enabled, but the maximum size can be raised' do
      let(:setrlimit_result) { [1, 2] }

      it 'raises the maximum size' do
        expect(Process).to receive(:setrlimit).with(:CORE, 2)

        enable_core_dumps
      end

      it 'logs a message informing it raised the limit' do
        expect(Kernel).to receive(:warn).with(/Raised core dump limit/)

        enable_core_dumps
      end
    end

    context 'when core dumps were not enabled' do
      let(:setrlimit_result) { [0, 1] }

      it 'enables core dumps' do
        expect(Process).to receive(:setrlimit).with(:CORE, 1)

        enable_core_dumps
      end

      it 'logs a message informing that core dumps were enabled' do
        expect(Kernel).to receive(:warn).with(/Enabled core dumps/)

        enable_core_dumps
      end
    end

    context 'when core dumps fail to be enabled' do
      let(:setrlimit_result) { [0, 1] }

      before do
        expect(Process).to receive(:setrlimit).with(:CORE, 1).and_raise(StandardError)
      end

      it 'logs a message informing that core dumps could not be enabled and does not propagate the exception' do
        expect(Kernel).to receive(:warn).with(/Failed to enable .* StandardError/)

        enable_core_dumps
      end
    end

    context 'when core pattern is available' do
      let(:setrlimit_result) { [0, 1] }

      before do
        expect(File).to receive(:read).with('/proc/sys/kernel/core_pattern').and_return("core-pattern-configured\n")
      end

      it 'logs a message including the core pattern' do
        expect(Kernel).to receive(:warn).with(/core-pattern-configured/)

        enable_core_dumps
      end
    end

    context 'when core pattern is not available' do
      let(:setrlimit_result) { [0, 1] }

      before do
        expect(File).to receive(:read).with('/proc/sys/kernel/core_pattern').and_raise(Errno::ENOENT)
      end

      it 'still enables core dumps' do
        expect(Process).to receive(:setrlimit).with(:CORE, 1)

        enable_core_dumps
      end

      it 'logs a message nothing the core pattern is not available' do
        expect(Kernel).to receive(:warn).with(/Could not open/)

        enable_core_dumps
      end
    end
  end
end
