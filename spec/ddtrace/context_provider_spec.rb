require 'spec_helper'

require 'ddtrace/context_provider'

RSpec.describe Datadog::DefaultContextProvider do
  let(:provider) { described_class.new }
  let(:local_context) { instance_double(Datadog::ThreadLocalContext) }
  let(:trace_context) { Datadog::Context.new }

  context '#context=' do
    subject(:context=) { provider.context = ctx }
    let(:ctx) { double }

    before { expect(Datadog::ThreadLocalContext).to receive(:new).and_return(local_context) }

    it do
      expect(local_context).to receive(:local=).with(ctx)
      subject
    end
  end

  context '#context' do
    subject(:context) { provider.context }

    before { expect(Datadog::ThreadLocalContext).to receive(:new).and_return(local_context) }

    context 'when given no arguments' do
      it do
        expect(local_context)
          .to receive(:local)
          .and_return(trace_context)

        subject
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

        subject
      end
    end
  end

  context 'when fork occurs' do
    before { skip 'Java not supported' if RUBY_PLATFORM == 'java' }

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

      ctx1 = provider1.context = Datadog::Context.new
      expect(provider1.context).to be(ctx1)
      expect(provider2.context).to_not be(ctx1)

      ctx2 = provider2.context = Datadog::Context.new
      expect(provider1.context).to be(ctx1)
      expect(provider2.context).to be(ctx2)
    end
  end
end

RSpec.describe Datadog::ThreadLocalContext do
  subject(:thread_local_context) { described_class.new }

  describe '#initialize' do
    it 'create one thread-local variable' do
      expect { subject }.to change { Thread.current.keys.size }.by(1)
    end
  end

  def thread_contexts
    Thread.current.keys.select { |k| k.to_s.start_with?('datadog_context_') }
  end

  describe '#local' do
    subject(:local) { thread_local_context.local }

    context 'with a second ThreadLocalContext' do
      let(:thread_local_context2) { described_class.new }

      it 'should not interfere with other ThreadLocalContext' do
        local_context = thread_local_context.local
        local_context2 = thread_local_context2.local

        expect(local_context).to_not eq(local_context2)
        expect(thread_local_context.local).to eq(local_context)
        expect(thread_local_context2.local).to eq(local_context2)
      end
    end

    context 'in another thread' do
      it 'create one thread-local variable per thread' do
        context = thread_local_context.local

        Thread.new do
          expect { @thread_context = thread_local_context.local }
            .to change { thread_contexts.size }.from(0).to(1)

          expect(@thread_context).to be_a Datadog::Context
        end.join

        expect(@thread_context).to_not eq(context)
      end
    end

    context 'given a thread' do
      subject(:local) { thread_local_context.local(thread) }
      let(:thread) { Thread.new {} }

      it 'retrieves the context for the provided thread' do
        is_expected.to be_a_kind_of(Datadog::Context)
        expect(local).to_not be(thread_local_context.local)
      end
    end

    context 'given a bad argument' do
      subject(:local) { thread_local_context.local('bad_arg') }
      it { expect { local }.to raise_error(ArgumentError) }
    end
  end

  describe '#local=' do
    subject(:local=) { thread_local_context.local = context }
    let(:context) { double }

    before { thread_local_context } # Force initialization

    it 'overrides thread-local variable' do
      expect { subject }.to_not(change { thread_contexts.size })

      expect(thread_local_context.local).to eq(context)
    end
  end
end
