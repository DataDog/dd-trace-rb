require 'spec_helper'

require 'datadog/tracing/context_provider'
require 'datadog/tracing/context'

RSpec.describe Datadog::Tracing::DefaultContextProvider do
  let(:provider) { described_class.new(**options) }
  let(:options) { {} }
  let(:trace_context) { Datadog::Tracing::Context.new }

  describe '#initialize' do
    context 'with default options' do
      it 'uses FiberIsolatedScope by default' do
        expect(provider.instance_variable_get(:@context)).to be_a(Datadog::Tracing::FiberIsolatedScope)
      end
    end

    context 'with scope: FiberIsolatedScope.new' do
      let(:options) { {scope: Datadog::Tracing::FiberIsolatedScope.new} }

      it 'uses FiberIsolatedScope' do
        expect(provider.instance_variable_get(:@context)).to be_a(Datadog::Tracing::FiberIsolatedScope)
      end
    end

    context 'with scope: ThreadScope.new' do
      let(:options) { {scope: Datadog::Tracing::ThreadScope.new} }

      it 'uses ThreadScope' do
        expect(provider.instance_variable_get(:@context)).to be_a(Datadog::Tracing::ThreadScope)
      end
    end
  end

  describe '#context=' do
    subject(:set_context) { provider.context = ctx }

    let(:scope) { instance_double(Datadog::Tracing::FiberIsolatedScope) }
    let(:options) { {scope: scope} }
    let(:ctx) { double }

    it do
      expect(scope).to receive(:current=).with(ctx)
      set_context
    end
  end

  describe '#context' do
    let(:scope) { instance_double(Datadog::Tracing::FiberIsolatedScope) }
    let(:options) { {scope: scope} }

    context 'when given no arguments' do
      subject(:context) { provider.context }

      it do
        expect(scope)
          .to receive(:current)
          .with(no_args)
          .and_return(trace_context)

        context
      end
    end

    context 'when given a key' do
      subject(:context) { provider.context(key) }

      let(:key) { double('key') }

      it do
        expect(scope)
          .to receive(:current)
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

  context 'with ThreadScope' do
    let(:options) { {scope: Datadog::Tracing::ThreadScope.new} }

    it 'shares context across fibers' do
      ctx = provider.context = Datadog::Tracing::Context.new
      expect(provider.context).to be(ctx)

      fiber_context = nil
      Fiber.new do
        fiber_context = provider.context
      end.resume

      expect(fiber_context).to be(ctx)
    end
  end

  context 'with FiberIsolatedScope' do
    let(:options) { {scope: Datadog::Tracing::FiberIsolatedScope.new} }

    it 'isolates context per fiber' do
      ctx = provider.context = Datadog::Tracing::Context.new
      expect(provider.context).to be(ctx)

      fiber_context = nil
      Fiber.new do
        fiber_context = provider.context
      end.resume

      expect(fiber_context).to_not be(ctx)
    end
  end
end

RSpec.describe Datadog::Tracing::ContextScope do
  describe '.next_instance_id' do
    it 'returns unique IDs' do
      id1 = described_class.next_instance_id
      id2 = described_class.next_instance_id

      expect(id1).to_not eq(id2)
    end
  end

  describe 'abstract methods' do
    let(:scope) { described_class.new }

    it 'raises NotImplementedError for set_current' do
      expect { scope.current = double }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for get_current via current' do
      # Need to bypass the initial current= in initialize
      scope = described_class.allocate
      scope.instance_variable_set(:@key, :test_key)

      expect { scope.current }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for get_current_for via current(storage)' do
      scope = described_class.allocate
      scope.instance_variable_set(:@key, :test_key)

      expect { scope.current(Thread.current) }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe Datadog::Tracing::FiberIsolatedScope do
  subject(:fiber_isolated_scope) { described_class.new }

  it 'is a subclass of ContextScope' do
    expect(described_class).to be < Datadog::Tracing::ContextScope
  end

  describe '#initialize' do
    it 'creates one fiber-local variable' do
      expect { fiber_isolated_scope }.to change { Thread.current.keys.size }.by(1)
    end
  end

  def fiber_contexts
    Thread.current.keys.select { |k| k.to_s.start_with?('datadog_context_') }
  end

  describe '#current' do
    subject(:current) { fiber_isolated_scope.current }

    context 'with a second FiberIsolatedScope' do
      let(:fiber_isolated_scope2) { described_class.new }

      it 'does not interfere with other FiberIsolatedScope' do
        local_context = fiber_isolated_scope.current
        local_context2 = fiber_isolated_scope2.current

        expect(local_context).to_not eq(local_context2)
        expect(fiber_isolated_scope.current).to eq(local_context)
        expect(fiber_isolated_scope2.current).to eq(local_context2)
      end
    end

    context 'in another fiber' do
      it 'creates one fiber-local variable per fiber' do
        main_fiber_context = fiber_isolated_scope.current
        other_fiber_context = nil

        Fiber.new do
          expect { other_fiber_context = fiber_isolated_scope.current }
            .to change { fiber_contexts.size }.from(0).to(1)
        end.resume

        expect(other_fiber_context).to be_a Datadog::Tracing::Context
        expect(other_fiber_context).to_not eq(main_fiber_context)
      end
    end

    context 'in another thread' do
      it 'creates one fiber-local variable per thread' do
        main_thread_context = fiber_isolated_scope.current
        other_thread_context = nil

        Thread.new do
          expect { other_thread_context = fiber_isolated_scope.current }
            .to change { fiber_contexts.size }.from(0).to(1)
        end.join

        expect(other_thread_context).to be_a Datadog::Tracing::Context
        expect(other_thread_context).to_not eq(main_thread_context)
      end
    end

    context 'given a storage object' do
      subject(:current) { fiber_isolated_scope.current(thread) }

      let(:queue) { Queue.new }
      let(:thread) { Thread.new { queue.pop } }

      after do
        queue << :done
        thread.join
      end

      it 'retrieves the context for the provided storage' do
        is_expected.to be_a_kind_of(Datadog::Tracing::Context)
        expect(current).to_not be(fiber_isolated_scope.current)
      end
    end
  end

  describe '#current=' do
    subject(:set_current) { fiber_isolated_scope.current = context }

    let(:context) { double }

    before { fiber_isolated_scope } # Force initialization

    it 'overrides fiber-local variable' do
      expect { set_current }.to_not(change { fiber_contexts.size })

      expect(fiber_isolated_scope.current).to eq(context)
    end
  end
end

RSpec.describe Datadog::Tracing::ThreadScope do
  subject(:thread_scope) { described_class.new }

  it 'is a subclass of ContextScope' do
    expect(described_class).to be < Datadog::Tracing::ContextScope
  end

  describe '#initialize' do
    it 'creates one thread-local variable' do
      expect { thread_scope }.to change { Thread.current.thread_variables.size }.by(1)
    end
  end

  def thread_contexts
    Thread.current.thread_variables.select { |k| k.to_s.start_with?('datadog_context_') }
  end

  describe '#current' do
    subject(:current) { thread_scope.current }

    context 'with a second ThreadScope' do
      let(:thread_scope2) { described_class.new }

      it 'does not interfere with other ThreadScope' do
        local_context = thread_scope.current
        local_context2 = thread_scope2.current

        expect(local_context).to_not eq(local_context2)
        expect(thread_scope.current).to eq(local_context)
        expect(thread_scope2.current).to eq(local_context2)
      end
    end

    context 'in another fiber' do
      it 'shares the same context across fibers' do
        main_fiber_context = thread_scope.current
        other_fiber_context = nil

        Fiber.new do
          other_fiber_context = thread_scope.current
        end.resume

        expect(other_fiber_context).to be_a Datadog::Tracing::Context
        expect(other_fiber_context).to eq(main_fiber_context)
      end
    end

    context 'in another thread' do
      it 'creates one thread-local variable per thread' do
        main_thread_context = thread_scope.current
        other_thread_context = nil

        Thread.new do
          expect { other_thread_context = thread_scope.current }
            .to change { thread_contexts.size }.from(0).to(1)
        end.join

        expect(other_thread_context).to be_a Datadog::Tracing::Context
        expect(other_thread_context).to_not eq(main_thread_context)
      end
    end

    context 'given a thread' do
      subject(:current) { thread_scope.current(thread) }

      let(:queue) { Queue.new }
      let(:thread) { Thread.new { queue.pop } }

      after do
        queue << :done
        thread.join
      end

      it 'retrieves the context for the provided thread' do
        is_expected.to be_a_kind_of(Datadog::Tracing::Context)
        expect(current).to_not be(thread_scope.current)
        expect(thread_scope.current(thread)).to be(current)
      end
    end
  end

  describe '#current=' do
    subject(:set_current) { thread_scope.current = context }

    let(:context) { double }

    before { thread_scope } # Force initialization

    it 'overrides thread-local variable' do
      expect { set_current }.to_not(change { thread_contexts.size })

      expect(thread_scope.current).to eq(context)
    end

    it 'shares the same context across fibers' do
      new_context = Datadog::Tracing::Context.new
      thread_scope.current = new_context

      fiber_context = nil
      Fiber.new do
        fiber_context = thread_scope.current
      end.resume

      expect(fiber_context).to be(new_context)
    end
  end
end
