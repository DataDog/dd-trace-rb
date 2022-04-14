# typed: ignore

require 'spec_helper'

require 'time'

require 'datadog/tracing/trace_operation'
require 'datadog/kit/identity'

RSpec.describe Datadog::Kit::Identity do
  subject(:trace_op) { Datadog::Tracing::TraceOperation.new }

  describe '#set_user' do
    it 'sets user on trace' do
      trace_op.measure('root') do
        described_class.set_user(trace_op, id: '42')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42')
    end

    it 'enforces :id presence' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, foo: 'bar') }.to raise_error(ArgumentError)
      end
    end

    it 'enforces String values' do
      trace_op.measure('root') do
        expect { described_class.set_user(trace_op, id: 42) }.to raise_error(TypeError)
      end
    end
  end
end
