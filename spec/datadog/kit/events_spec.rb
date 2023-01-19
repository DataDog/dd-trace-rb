# typed: ignore

require 'spec_helper'

require 'time'

require 'datadog/tracing/trace_operation'
require 'datadog/kit/events'

RSpec.describe Datadog::Kit::Events do
  subject(:trace_op) { Datadog::Tracing::TraceOperation.new }

  describe '#track_login' do
    context 'login success' do
      it 'sets event tracking key on trace' do
        trace_op.measure('root') do
          described_class.track_login(trace_op, user: { id: '42' }, success: true)
        end
        trace = trace_op.flush!
        expect(trace.send(:meta)).to include('appsec.events.users.login.success.track' => 'true')
      end

      it 'sets user id on trace' do
        trace_op.measure('root') do
          described_class.track_login(trace_op, user: { id: '42' }, success: true)
        end
        trace = trace_op.flush!
        expect(trace.send(:meta)).to include('usr.id' => '42')
      end

      it 'sets other keys on trace' do
        trace_op.measure('root') do
          described_class.track_login(trace_op, user: { id: '42' }, success: true, foo: 'bar')
        end
        trace = trace_op.flush!
        expect(trace.send(:meta)).to include('usr.id' => '42', 'appsec.events.users.login.success.foo' => 'bar')
      end
    end

    context 'login failure' do
      it 'sets event tracking key on trace' do
        trace_op.measure('root') do
          described_class.track_login(trace_op, user: { id: '42' }, success: false)
        end
        trace = trace_op.flush!
        expect(trace.send(:meta)).to include('appsec.events.users.login.failure.track' => 'true')
      end

      it 'sets user id on trace' do
        trace_op.measure('root') do
          described_class.track_login(trace_op, user: { id: '42' }, success: false)
        end
        trace = trace_op.flush!
        expect(trace.send(:meta)).to include('appsec.events.users.login.failure.usr.id' => '42')
      end

      it 'sets other keys on trace' do
        trace_op.measure('root') do
          described_class.track_login(trace_op, user: { id: '42' }, success: false, foo: 'bar')
        end
        trace = trace_op.flush!
        expect(trace.send(:meta)).to include('appsec.events.users.login.failure.foo' => 'bar')
      end
    end
  end

  describe '#track' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do
        described_class.track('foo', trace_op)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.foo.track' => 'true')
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do
        described_class.track('foo', trace_op, bar: 'baz')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.foo.bar' => 'baz')
    end
  end
end
