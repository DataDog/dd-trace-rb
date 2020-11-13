require 'spec_helper'
require 'ddtrace/profiling'
require 'ddtrace/profiling/ext/forking'

RSpec.describe Datadog::Profiling::Ext::Forking do
  describe '::supported?' do
    subject(:supported?) { described_class.supported? }

    context 'when MRI Ruby is used' do
      before { stub_const('RUBY_PLATFORM', 'x86_64-linux') }
      it { is_expected.to be true }
    end

    context 'when JRuby is used' do
      before { stub_const('RUBY_PLATFORM', 'java') }
      it { is_expected.to be false }
    end
  end

  describe '::apply!' do
    subject(:apply!) { described_class.apply! }

    let(:toplevel_receiver) do
      if TOPLEVEL_BINDING.respond_to?(:receiver)
        TOPLEVEL_BINDING.receiver
      else
        TOPLEVEL_BINDING.eval('self')
      end
    end

    around do |example|
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
      expect(::Process.ancestors.include?(described_class::Kernel)).to be false
      expect(::Kernel.ancestors.include?(described_class::Kernel)).to be false
      # Can't assert this because top level can't be reverted; can't guarantee pristine state.
      # expect(toplevel_receiver.class.ancestors.include?(described_class::Kernel)).to be false

      expect(::Process.method(:fork).source_location).to be nil
      expect(::Kernel.method(:fork).source_location).to be nil
      # Can't assert this because top level can't be reverted; can't guarantee pristine state.
      # expect(toplevel_receiver.method(:fork).source_location).to be nil
    end

    context 'when forking is supported' do
      before { skip 'Forking not supported' unless described_class.supported? }

      it 'applies the Kernel patch' do
        # NOTE: There's no way to undo a modification of the TOPLEVEL_BINDING.
        #       The results of this will carry over into other tests...
        #       Just assert that the receiver was patched instead.
        #       Unfortunately means we can't test if "fork" works in main Object.
        expect(toplevel_receiver)
          .to receive(:extend)
          .with(described_class::Kernel)

        apply!

        expect(::Process.ancestors).to include(described_class::Kernel)
        expect(::Kernel.ancestors).to include(described_class::Kernel)

        expect(::Process.method(:fork).source_location.first).to match(%r{.*ddtrace/profiling/ext/forking.rb})
        expect(::Kernel.method(:fork).source_location.first).to match(%r{.*ddtrace/profiling/ext/forking.rb})
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
end

RSpec.describe Datadog::Profiling::Ext::Forking::Kernel do
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

    before do
      # TODO: This test breaks other tests when Forking#apply! runs first in Ruby < 2.3
      #       Unclear whether its the setup from this test, or cleanup elsewhere (e.g. spec_helper.rb)
      #       Either way, #apply! causes callbacks not to work; Forking patch is
      #       not hooking in properly. See `fork_class.method(:fork).source_location`
      #       and `fork.class.ancestors` vs `fork.singleton_class.ancestors`.
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3')
        skip 'Test is unstable for Ruby < 2.3'
      end
    end
  end

  shared_context 'at_fork callbacks' do
    let(:prepare) { double('prepare') }
    let(:child) { double('child') }
    let(:parent) { double('parent') }

    before do
      fork_class.at_fork(:prepare) { prepare.call }
      fork_class.at_fork(:child) { child.call }
      fork_class.at_fork(:parent) { parent.call }
    end

    after do
      described_class.at_fork_blocks.clear
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
            expect(prepare).to receive(:call).ordered
            expect(child).to_not receive(:call)
            expect(parent).to receive(:call).ordered

            is_expected.to be fork_result
          end
        end

        context 'and returns from the child context' do
          # By setting the fork result = nil, we're
          # simulating #fork running in the child process.
          let(:fork_result) { nil }

          it do
            expect(prepare).to receive(:call).ordered
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
            expect(prepare).to receive(:call).ordered
            expect(child).to receive(:call).ordered
            expect(parent).to receive(:call).ordered

            is_expected.to be fork_result
          end
        end
      end
    end

    describe '#at_fork' do
      include_context 'at_fork callbacks'

      let(:callback) { double('callback') }
      let(:block) { proc { callback.call } }

      context 'by default' do
        subject(:at_fork) do
          fork_class.at_fork(&block)
        end

        it 'adds a :prepare callback' do
          at_fork

          expect(prepare).to receive(:call).ordered
          expect(callback).to receive(:call).ordered
          expect(child).to receive(:call).ordered
          expect(parent).to receive(:call).ordered

          fork_class.fork {}
        end
      end

      context 'given a stage' do
        subject(:at_fork) do
          fork_class.at_fork(stage, &block)
        end

        context ':prepare' do
          let(:stage) { :prepare }

          it 'adds a prepare callback' do
            at_fork

            expect(prepare).to receive(:call).ordered
            expect(callback).to receive(:call).ordered
            expect(child).to receive(:call).ordered
            expect(parent).to receive(:call).ordered

            fork_class.fork {}
          end
        end

        context ':child' do
          let(:stage) { :child }

          it 'adds a child callback' do
            at_fork

            expect(prepare).to receive(:call).ordered
            expect(child).to receive(:call).ordered
            expect(callback).to receive(:call).ordered
            expect(parent).to receive(:call).ordered

            fork_class.fork {}
          end
        end

        context ':parent' do
          let(:stage) { :parent }

          it 'adds a parent callback' do
            at_fork

            expect(prepare).to receive(:call).ordered
            expect(child).to receive(:call).ordered
            expect(parent).to receive(:call).ordered
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
        expect(prepare).to receive(:call).ordered
        expect(child).to receive(:call).ordered
        expect(parent).to receive(:call).ordered

        fork_class.fork {}
      end

      it 'applies the callback to the other class' do
        expect(prepare).to receive(:call).ordered
        expect(child).to receive(:call).ordered
        expect(parent).to receive(:call).ordered

        other_fork_class.fork {}
      end
    end
  end
end
