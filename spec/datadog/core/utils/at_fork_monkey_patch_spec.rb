require 'datadog/core/utils/at_fork_monkey_patch'

RSpec.describe Datadog::Core::Utils::AtForkMonkeyPatch do
  before { skip 'Forking not supported' unless Datadog::Core::Utils::AtForkMonkeyPatch.supported? } # rubocop:disable RSpec/DescribedClass

  describe '::apply!' do
    subject(:apply!) { described_class.apply! }

    context 'when forking is supported' do
      before do
        if ::Process.singleton_class.ancestors.include?(Datadog::Core::Utils::AtForkMonkeyPatch::ProcessMonkeyPatch)
          skip 'Monkey patch already applied (unclean state)'
        end
      end

      let(:toplevel_receiver) { TOPLEVEL_BINDING.receiver }

      context 'on Ruby 3.0 or below' do
        before { skip 'Test applies only to Ruby 3.0 or below' if RUBY_VERSION >= '3.1' }

        it 'applies the monkey patch' do
          expect_in_fork do
            apply!

            expect(::Process.ancestors).to include(described_class::KernelMonkeyPatch)
            expect(::Process.ancestors).to include(described_class::ProcessMonkeyPatch)
            expect(::Kernel.ancestors).to include(described_class::KernelMonkeyPatch)
            expect(toplevel_receiver.class.ancestors).to include(described_class::KernelMonkeyPatch)

            expect(::Process.method(:fork).source_location.first).to match(/.*at_fork_monkey_patch.rb/)
            expect(::Process.method(:daemon).source_location.first).to match(/.*at_fork_monkey_patch.rb/)
            expect(::Kernel.method(:fork).source_location.first).to match(/.*at_fork_monkey_patch.rb/)
            expect(toplevel_receiver.method(:fork).source_location.first).to match(/.*at_fork_monkey_patch.rb/)
          end
        end
      end

      context 'on Ruby 3.1 or above' do
        before { skip 'Test applies only to Ruby 3.1 or above' if RUBY_VERSION < '3.1' }

        it 'applies the monkey patch' do
          expect_in_fork do
            apply!

            expect(::Process.ancestors).to include(described_class::ProcessMonkeyPatch)
            expect(::Process.method(:daemon).source_location.first).to match(/.*at_fork_monkey_patch.rb/)
            expect(::Process.method(:_fork).source_location.first).to match(/.*at_fork_monkey_patch.rb/)
          end
        end

        it 'does not monkey patch Kernel/Object' do
          expect_in_fork do
            apply!

            expect(::Process.ancestors).to_not include(described_class::KernelMonkeyPatch)
            expect(::Kernel.ancestors).to_not include(described_class::KernelMonkeyPatch)
            expect(toplevel_receiver.class.ancestors).to_not include(described_class::KernelMonkeyPatch)

            expect(::Process.method(:fork).source_location&.first).to_not match(/.*at_fork_monkey_patch.rb/)
            expect(::Kernel.method(:fork).source_location&.first).to_not match(/.*at_fork_monkey_patch.rb/)
            expect(toplevel_receiver.method(:fork).source_location&.first).to_not match(/.*at_fork_monkey_patch.rb/)
          end
        end
      end
    end

    context 'when forking is not supported' do
      before do
        allow(described_class)
          .to receive(:supported?)
          .and_return(false)
      end

      it 'skips the monkey patch' do
        is_expected.to be false
      end
    end
  end

  describe Datadog::Core::Utils::AtForkMonkeyPatch::KernelMonkeyPatch do
    shared_context 'fork class' do
      def new_fork_class
        Class.new.tap do |c|
          c.singleton_class.class_eval do
            prepend Datadog::Core::Utils::AtForkMonkeyPatch::KernelMonkeyPatch

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
          b&.call
          fork_result
        end
      end
    end

    shared_context 'at_fork callbacks' do
      let(:before_fork) { double('before') }
      let(:parent) { double('parent') }
      let(:child) { double('child') }

      before do
        Datadog::Core::Utils::AtForkMonkeyPatch.at_fork(:before) { before_fork.call }
        Datadog::Core::Utils::AtForkMonkeyPatch.at_fork(:parent) { parent.call }
        Datadog::Core::Utils::AtForkMonkeyPatch.at_fork(:child) { child.call }
      end

      after do
        Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_BEFORE_BLOCKS).clear
        Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_PARENT_BLOCKS).clear
        Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_CHILD_BLOCKS).clear
      end
    end

    context 'when applied to a class with forking' do
      include_context 'fork class'

      it do
        is_expected.to respond_to(:fork)
      end

      describe '#fork' do
        context 'when a block is not provided' do
          include_context 'at_fork callbacks'

          subject(:fork) { fork_class.fork }

          context 'and returns from the parent context' do
            let(:fork_result) { 1234 } # simulate parent: result is a pid

            it 'runs the before and parent callbacks but not the child callbacks' do
              expect(before_fork).to receive(:call).ordered
              expect(parent).to receive(:call).ordered
              expect(child).to_not receive(:call)

              is_expected.to be fork_result
            end
          end

          context 'and returns from the child context' do
            let(:fork_result) { nil } # simulate child: result is a nil

            it 'runs the before and child callbacks but not the parent callbacks' do
              expect(before_fork).to receive(:call).ordered
              expect(child).to receive(:call).ordered
              expect(parent).to_not receive(:call)

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
              # The stubbed fork invokes the wrapped block (running the child
              # callbacks) and then returns a non-nil pid (parent branch).
              expect(before_fork).to receive(:call).ordered
              expect(child).to receive(:call).ordered
              expect(parent).to receive(:call).ordered

              is_expected.to be fork_result
            end
          end
        end
      end
    end
  end

  describe Datadog::Core::Utils::AtForkMonkeyPatch::ProcessMonkeyPatch do
    let(:_fork_result) { nil }
    let(:process_module) do
      result = _fork_result

      Module.new do
        def self.daemon(nochdir = nil, noclose = nil)
          [nochdir, noclose]
        end
        define_singleton_method(:_fork) { result }
      end
    end
    let(:before_callback) { double('before', call: true) }
    let(:parent_callback) { double('parent', call: true) }
    let(:child_callback) { double('child', call: true) }

    before do
      process_module.singleton_class.prepend(described_class)

      Datadog::Core::Utils::AtForkMonkeyPatch.at_fork(:before) { before_callback.call }
      Datadog::Core::Utils::AtForkMonkeyPatch.at_fork(:parent) { parent_callback.call }
      Datadog::Core::Utils::AtForkMonkeyPatch.at_fork(:child) { child_callback.call }
    end

    after do
      Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_BEFORE_BLOCKS).clear
      Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_PARENT_BLOCKS).clear
      Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_CHILD_BLOCKS).clear
    end

    describe '.daemon' do
      it 'calls the before and child at_fork callbacks around Process.daemon, but not the parent callbacks' do
        expect(process_module).to receive(:daemon).and_call_original
        expect(before_callback).to receive(:call)
        expect(child_callback).to receive(:call)
        # `daemon` kills the parent, so the parent callbacks never run.
        expect(parent_callback).to_not receive(:call)

        process_module.daemon
      end

      it 'runs the before callback before the child callback' do
        calls = []
        described_class_blocks = Datadog::Core::Utils::AtForkMonkeyPatch
        described_class_blocks.const_get(:AT_FORK_BEFORE_BLOCKS).clear
        described_class_blocks.const_get(:AT_FORK_CHILD_BLOCKS).clear
        described_class_blocks.at_fork(:before) { calls << :before }
        described_class_blocks.at_fork(:child) { calls << :child }

        process_module.daemon

        expect(calls).to eq(%i[before child])
      end

      it 'passes any arguments to Process.daemon and returns its results' do
        expect(process_module.daemon(:arg1, :arg2)).to eq([:arg1, :arg2])
      end
    end

    describe '_fork' do
      context 'in the child process' do
        let(:_fork_result) { 0 }

        it 'triggers the before and child callbacks but not the parent callbacks' do
          expect(before_callback).to receive(:call).ordered
          expect(child_callback).to receive(:call).ordered
          expect(parent_callback).to_not receive(:call)

          expect(process_module._fork).to be 0
        end

        it 'returns the result from _fork' do
          expect(process_module._fork).to be _fork_result
        end
      end

      context 'in the parent process' do
        let(:_fork_result) { 1234 }

        it 'triggers the before and parent callbacks but not the child callbacks' do
          expect(before_callback).to receive(:call).ordered
          expect(parent_callback).to receive(:call).ordered
          expect(child_callback).to_not receive(:call)

          process_module._fork
        end

        it 'returns the result from _fork' do
          expect(process_module._fork).to be _fork_result
        end
      end
    end
  end

  describe '::at_fork and ::run_at_fork_blocks' do
    after do
      Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_BEFORE_BLOCKS).clear
      Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_PARENT_BLOCKS).clear
      Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_CHILD_BLOCKS).clear
    end

    %i[before parent child].each do |stage|
      it "registers and runs #{stage.inspect} blocks in registration order" do
        calls = []
        described_class.at_fork(stage) { calls << :first }
        described_class.at_fork(stage) { calls << :second }

        described_class.run_at_fork_blocks(stage)

        expect(calls).to eq(%i[first second])
      end
    end

    it 'keeps the stages independent' do
      calls = []
      described_class.at_fork(:before) { calls << :before }
      described_class.at_fork(:parent) { calls << :parent }
      described_class.at_fork(:child) { calls << :child }

      described_class.run_at_fork_blocks(:before)
      expect(calls).to eq(%i[before])

      described_class.run_at_fork_blocks(:child)
      expect(calls).to eq(%i[before child])
    end

    it 'raises ArgumentError for an unknown stage when registering' do
      expect { described_class.at_fork(:nonsense) {} }.to raise_error(ArgumentError, /Unsupported stage nonsense/)
    end

    it 'raises ArgumentError for an unknown stage when running' do
      expect { described_class.run_at_fork_blocks(:nonsense) }.to raise_error(ArgumentError, /Unsupported stage nonsense/)
    end

    it 'raises ArgumentError when no block is given' do
      expect { described_class.at_fork(:child) }.to raise_error(ArgumentError, /Missing block argument/)
    end
  end
end
