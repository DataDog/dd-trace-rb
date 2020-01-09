require 'spec_helper'

require 'ddtrace/context_provider'

RSpec.describe Datadog::ThreadLocalContext do
  subject(:thread_local_context) { described_class.new }

  describe '#local' do
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
  end
end
