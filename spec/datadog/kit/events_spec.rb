# typed: ignore

require 'spec_helper'

require 'time'

require 'datadog/tracing/trace_operation'
require 'datadog/kit/events'

RSpec.describe Datadog::Kit::Events do
  subject(:trace_op) { Datadog::Tracing::TraceOperation.new }

  describe '#track_login_success' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do
        described_class.track_login_success(trace_op, user: { id: '42' })
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.users.login.success.track' => 'true')
    end

    it 'sets user id on trace' do
      trace_op.measure('root') do
        described_class.track_login_success(trace_op, user: { id: '42' })
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42')
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do
        described_class.track_login_success(trace_op, user: { id: '42' }, foo: 'bar')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('usr.id' => '42', 'appsec.events.users.login.success.foo' => 'bar')
    end
  end

  describe '#track_login_failure' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.users.login.failure.track' => 'true')
    end

    it 'sets user id on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.users.login.failure.usr.id' => '42')
    end

    it 'sets user existence on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.users.login.failure.usr.exists' => 'true')
    end

    it 'sets user non-existence  on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: false)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.users.login.failure.usr.exists' => 'false')
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true, foo: 'bar')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.users.login.failure.foo' => 'bar')
    end
  end

  describe '#track' do
    it 'rejects unexpected namespaces' do
      trace_op.measure('root') do
        expect { described_class.track(:foo, 'bar', trace_op) }.to raise_error ArgumentError
      end

      trace = trace_op.flush!
      expect(trace.send(:meta)).to_not include('foo.events.bar.track' => 'true')
    end

    it 'sets event tracking key on trace' do
      trace_op.measure('root') do
        described_class.track(:appsec, 'foo', trace_op)
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.foo.track' => 'true')
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do
        described_class.track(:appsec, 'foo', trace_op, bar: 'baz')
      end
      trace = trace_op.flush!
      expect(trace.send(:meta)).to include('appsec.events.foo.bar' => 'baz')
    end
  end
end
