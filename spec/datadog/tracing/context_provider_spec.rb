require 'spec_helper'

require 'datadog/tracing/context_provider'
require 'datadog/tracing/context'

RSpec.describe Datadog::Tracing::DefaultContextProvider do
  let(:provider) { described_class.new }
  let(:local_context) { instance_double(Datadog::Tracing::FiberLocalContext) }
  let(:trace_context) { Datadog::Tracing::Context.new }

  describe '#context=' do
    subject(:set_context) { provider.context = ctx }

    let(:ctx) { double }

    before { expect(Datadog::Tracing::FiberLocalContext).to receive(:new).and_return(local_context) }

    it do
      expect(local_context).to receive(:local=).with(ctx)
      set_context
    end
  end

  describe '#context' do
    subject(:context) { provider.context }

    before { expect(Datadog::Tracing::FiberLocalContext).to receive(:new).and_return(local_context) }

    context 'when given no arguments' do
      it do
        expect(local_context)
          .to receive(:local)
          .and_return(trace_context)

        context
      end
    end

    context 'when given a key' do
      subject(:context) { provider.context(key) }

      let(:key) { double('key') }

      it do
        expect(local_context)
          .to receive(:local)
          .with(key)
          .and_return(trace_context)

        context
      end
    end
  end

  context 'when fork occurs' do
    before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

    it 'clones the context and returns the clone' do
      # Initialize a context for the current process
      parent_context = provider.context
      expect(parent_context.forked?).to be false

      # Fork the process, clone context.
      expect_in_fork do
        expect(parent_context).to receive(:fork_clone).and_call_original
        child_context = provider.context

        # Check context changed
        expect(child_context).to_not be parent_context

        # Check context doesn't change again
        expect(provider.context).to be(child_context)
      end
    end
  end

  context 'with multiple instances' do
    it 'holds independent values for each instance' do
      provider1 = described_class.new
      provider2 = described_class.new

      ctx1 = provider1.context = Datadog::Tracing::Context.new
      expect(provider1.context).to be(ctx1)
      expect(provider2.context).to_not be(ctx1)

      ctx2 = provider2.context = Datadog::Tracing::Context.new
      expect(provider1.context).to be(ctx1)
      expect(provider2.context).to be(ctx2)
    end
  end
end

RSpec.describe Datadog::Tracing::FiberLocalContext do
  subject(:fiber_local_context) { described_class.new }

  describe '#initialize' do
    it 'create one fiber-local variable' do
      expect { fiber_local_context }.to change { Thread.current.keys.size }.by(1)
    end
  end

  def fiber_contexts
    Thread.current.keys.select { |k| k.to_s.start_with?('datadog_context_') }
  end

  describe '#local' do
    subject(:local) { fiber_local_context.local }

    context 'with a second FiberLocalContext' do
      let(:fiber_local_context2) { described_class.new }

      it 'does not interfere with other FiberLocalContext' do
        local_context = fiber_local_context.local
        local_context2 = fiber_local_context2.local

        expect(local_context).to_not eq(local_context2)
        expect(fiber_local_context.local).to eq(local_context)
        expect(fiber_local_context2.local).to eq(local_context2)
      end
    end

    context 'in another fiber' do
      it 'create one fiber-local variable per fiber' do
        main_fiber_context = fiber_local_context.local
        other_fiber_context = nil

        Fiber.new do
          expect { other_fiber_context = fiber_local_context.local }
            .to change { fiber_contexts.size }.from(0).to(1)
        end.resume

        expect(other_fiber_context).to be_a Datadog::Tracing::Context
        expect(other_fiber_context).to_not eq(main_fiber_context)
      end
    end

    context 'in another thread' do
      it 'create one fiber-local variable per thread' do
        main_thread_context = fiber_local_context.local
        other_thread_context = nil

        Thread.new do
          expect { other_thread_context = fiber_local_context.local }
            .to change { fiber_contexts.size }.from(0).to(1)
        end.join

        expect(other_thread_context).to be_a Datadog::Tracing::Context
        expect(other_thread_context).to_not eq(main_thread_context)
      end
    end

    context 'given a thread' do
      subject(:local) { fiber_local_context.local(thread) }

      let(:thread) { Thread.new {} }

      it 'retrieves the context for the provided thread' do
        is_expected.to be_a_kind_of(Datadog::Tracing::Context)
        expect(local).to_not be(fiber_local_context.local)
      end
    end
  end

  describe '#local=' do
    subject(:set_local) { fiber_local_context.local = context }

    let(:context) { double }

    before { fiber_local_context } # Force initialization

    it 'overrides fiber-local variable' do
      expect { set_local }.to_not(change { fiber_contexts.size })

      expect(fiber_local_context.local).to eq(context)
    end
  end
end
