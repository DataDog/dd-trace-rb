require 'datadog/profiling/spec_helper'

require 'datadog/profiling/ext/forking'

RSpec.describe Datadog::Profiling::Ext::Forking do
  before { skip_if_profiling_not_supported(self) }

  describe '::apply!' do
    subject(:apply!) { described_class.apply! }

    let(:toplevel_receiver) { TOPLEVEL_BINDING.receiver }

    context 'when forking is supported' do
      around do |example|
        # NOTE: Do not move this to a before, since we also want to skip the around as well
        skip 'Forking not supported' unless described_class.supported?

        if ::Process.singleton_class.ancestors.include?(Datadog::Profiling::Ext::Forking::Kernel)
          skip 'Unclean Process class state.'
        end

        unmodified_process_class = ::Process.dup
        unmodified_kernel_class = ::Kernel.dup

        example.run

        # Clean up classes
        Object.send(:remove_const, :Process)
        Object.const_set('Process', unmodified_process_class)

        Object.send(:remove_const, :Kernel)
        Object.const_set('Kernel', unmodified_kernel_class)

        # Check for leaks (make sure test is properly cleaned up)
        expect(::Process <= described_class::Kernel).to be nil
        expect(::Process <= described_class::ProcessDaemonPatch).to be nil
        expect(::Kernel <= described_class::Kernel).to be nil
        # Can't assert this because top level can't be reverted; can't guarantee pristine state.
        # expect(toplevel_receiver.class.ancestors.include?(described_class::Kernel)).to be false

        expect(::Process.method(:fork).source_location).to be nil
        expect(::Kernel.method(:fork).source_location).to be nil
        expect(::Process.method(:daemon).source_location).to be nil
        # Can't assert this because top level can't be reverted; can't guarantee pristine state.
        # expect(toplevel_receiver.method(:fork).source_location).to be nil
      end

      it 'applies the Kernel patch' do
        # NOTE: There's no way to undo a modification of the TOPLEVEL_BINDING.
        #       The results of this will carry over into other tests...
        #       Just assert that the receiver was patched instead.
        #       Unfortunately means we can't test if "fork" works in main Object.

        apply!

        expect(::Process.ancestors).to include(described_class::Kernel)
        expect(::Process.ancestors).to include(described_class::ProcessDaemonPatch)
        expect(::Kernel.ancestors).to include(described_class::Kernel)
        expect(toplevel_receiver.class.ancestors).to include(described_class::Kernel)

        expect(::Process.method(:fork).source_location.first).to match(%r{.*datadog/profiling/ext/forking.rb})
        expect(::Process.method(:daemon).source_location.first).to match(%r{.*datadog/profiling/ext/forking.rb})
        expect(::Kernel.method(:fork).source_location.first).to match(%r{.*datadog/profiling/ext/forking.rb})
        expect(toplevel_receiver.method(:fork).source_location.first).to match(%r{.*datadog/profiling/ext/forking.rb})
      end
    end

    context 'when forking is not supported' do
      before do
        allow(described_class)
          .to receive(:supported?)
          .and_return(false)
      end

      it 'skips the Kernel patch' do
        is_expected.to be false
      end
    end
  end

  describe Datadog::Profiling::Ext::Forking::Kernel do
    before { skip 'Forking not supported' unless Datadog::Profiling::Ext::Forking.supported? }

    shared_context 'fork class' do
      def new_fork_class
        Class.new.tap do |c|
          c.singleton_class.class_eval do
            prepend Datadog::Profiling::Ext::Forking::Kernel

            def fork(&block)
              Kernel.fork(&block)
            end
          end
        end
      end

      subject(:fork_class) { new_fork_class }

      let(:fork_result) { :fork_result }

      before do
        # Stub out actual forking, return mock result.
        # This also makes callback order deterministic.
        allow(Kernel).to receive(:fork) do |*_args, &b|
          b.call unless b.nil?
          fork_result
        end
      end
    end

    shared_context 'at_fork callbacks' do
      let(:child) { double('child') }

      before do
        fork_class.at_fork(:child) { child.call }
      end

      after do
        described_class.ddtrace_at_fork_blocks.clear
      end
    end

    context 'when applied to a class with forking' do
      include_context 'fork class'

      it do
        is_expected.to respond_to(:fork)
        is_expected.to respond_to(:at_fork)
      end

      describe '#fork' do
        context 'when a block is not provided' do
          include_context 'at_fork callbacks'

          subject(:fork) { fork_class.fork }

          context 'and returns from the parent context' do
            # By setting the fork result = integer, we're
            # simulating #fork running in the parent process.
            let(:fork_result) { rand(100) }

            it do
              expect(child).to_not receive(:call)

              is_expected.to be fork_result
            end
          end

          context 'and returns from the child context' do
            # By setting the fork result = nil, we're
            # simulating #fork running in the child process.
            let(:fork_result) { nil }

            it do
              expect(child).to receive(:call)

              is_expected.to be nil
            end
          end
        end

        context 'when a block is provided' do
          subject(:fork) { fork_class.fork(&block) }

          let(:block) { proc {} }

          context 'when no callbacks are configured' do
            it 'passes through to original #fork' do
              expect { |b| fork_class.fork(&b) }.to yield_control
              is_expected.to be fork_result
            end
          end

          context 'when callbacks are configured' do
            include_context 'at_fork callbacks'

            it 'invokes all the callbacks in order' do
              expect(child).to receive(:call)

              is_expected.to be fork_result
            end
          end
        end
      end

      describe '#at_fork' do
        include_context 'at_fork callbacks'

        let(:callback) { double('callback') }
        let(:block) { proc { callback.call } }

        context 'given a stage' do
          subject(:at_fork) do
            fork_class.at_fork(stage, &block)
          end

          context ':child' do
            let(:stage) { :child }

            it 'adds a child callback' do
              at_fork

              expect(child).to receive(:call).ordered
              expect(callback).to receive(:call).ordered

              fork_class.fork {}
            end
          end
        end
      end
    end

    context 'when applied to multiple classes with forking' do
      include_context 'fork class'

      let(:other_fork_class) { new_fork_class }

      context 'and #at_fork is called in one' do
        include_context 'at_fork callbacks'

        it 'applies the callback to the original class' do
          expect(child).to receive(:call)

          fork_class.fork {}
        end

        it 'applies the callback to the other class' do
          expect(child).to receive(:call)

          other_fork_class.fork {}
        end
      end
    end
  end

  describe Datadog::Profiling::Ext::Forking::ProcessDaemonPatch do
    let(:process_module) { Module.new { def self.daemon(nochdir = nil, noclose = nil); end } }
    let(:child_callback) { double('child', call: true) }

    before do
      allow(process_module).to receive(:daemon)

      process_module.singleton_class.prepend(Datadog::Profiling::Ext::Forking::Kernel)
      process_module.singleton_class.prepend(described_class)

      process_module.at_fork(:child) { child_callback.call }
    end

    after do
      Datadog::Profiling::Ext::Forking::Kernel.ddtrace_at_fork_blocks.clear
    end

    it 'calls the child at_fork callbacks after calling Process.daemon' do
      expect(process_module).to receive(:daemon).ordered
      expect(child_callback).to receive(:call).ordered

      process_module.daemon
    end

    it 'passes any arguments to Process.daemon' do
      expect(process_module).to receive(:daemon).with(true, true)

      process_module.daemon(true, true)
    end

    it 'returns the result of calling Process.daemon' do
      expect(process_module).to receive(:daemon).and_return(:process_daemon_result)

      expect(process_module.daemon).to be :process_daemon_result
    end
  end
end
