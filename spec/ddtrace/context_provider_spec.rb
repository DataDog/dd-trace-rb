require 'spec_helper'

require 'ddtrace/context_provider'

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
