require 'spec_helper'

require 'time'

require 'datadog/tracing/trace_operation'
require 'datadog/kit/appsec/events'

RSpec.describe Datadog::Kit::AppSec::Events do
  subject(:trace_op) { Datadog::Tracing::TraceOperation.new }

  let(:trace) { trace_op.flush! }
  let(:meta) { trace.send(:meta) }

  describe '#track_login_success' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do
        described_class.track_login_success(trace_op, user: { id: '42' })
      end
      expect(meta).to include('appsec.events.users.login.success.track' => 'true')
    end

    it 'sets successful user id on trace' do
      trace_op.measure('root') do
        described_class.track_login_success(trace_op, user: { id: '42' })
      end
      expect(meta).to include('usr.id' => '42')
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do
        described_class.track_login_success(trace_op, user: { id: '42' }, foo: 'bar')
      end
      expect(meta).to include('usr.id' => '42', 'appsec.events.users.login.success.foo' => 'bar')
    end
  end

  describe '#track_login_failure' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)
      end
      expect(meta).to include('appsec.events.users.login.failure.track' => 'true')
    end

    it 'sets failing user id on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)
      end
      expect(meta).to include('appsec.events.users.login.failure.usr.id' => '42')
    end

    it 'sets user existence on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)
      end
      expect(meta).to include('appsec.events.users.login.failure.usr.exists' => 'true')
    end

    it 'sets user non-existence  on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: false)
      end
      expect(meta).to include('appsec.events.users.login.failure.usr.exists' => 'false')
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true, foo: 'bar')
      end
      expect(meta).to include('appsec.events.users.login.failure.foo' => 'bar')
    end
  end

  describe '#track' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do
        described_class.track('foo', trace_op)
      end
      expect(meta).to include('appsec.events.foo.track' => 'true')
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do
        described_class.track('foo', trace_op, bar: 'baz')
      end
      expect(meta).to include('appsec.events.foo.bar' => 'baz')
    end
  end
end
