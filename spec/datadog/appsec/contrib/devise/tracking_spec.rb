require 'datadog/appsec/spec_helper'

require 'datadog/appsec/contrib/devise/tracking'

RSpec.describe Datadog::AppSec::Contrib::Devise::Tracking do
  let(:trace_op) { Datadog::Tracing::TraceOperation.new }
  let(:auto_mode) { Datadog.configuration.appsec.track_user_events.mode.to_s }

  describe '#track_login_success' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_success(trace_op, span, user_id: '42')
        expect(span.tags).to include('appsec.events.users.login.success.track' => 'true')
        expect(span.tags).to include('_dd.appsec.events.users.login.success.auto.mode' => auto_mode)
      end
    end

    it 'sets successful user id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_success(trace_op, span, user_id: '42')
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_success(trace_op, span, user_id: '42', foo: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'appsec.events.users.login.success.foo' => 'bar')
      end
    end

    it 'if user ID is nil do not set user tag' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_success(trace_op, span, user_id: nil, foo: 'bar')
        expect(span.tags).to_not include('usr.id' => '42')
      end
    end
  end

  describe '#track_login_failure' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, span, user_id: '42', user_exists: true)
        expect(span.tags).to include('appsec.events.users.login.failure.track' => 'true')
        expect(span.tags).to include('_dd.appsec.events.users.login.failure.auto.mode' => auto_mode)
      end
    end

    it 'sets failing user id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, span, user_id: '42', user_exists: true)
        expect(span.tags).to include('appsec.events.users.login.failure.usr.id' => '42')
      end
    end

    it 'do not sets failing user id on trace if user_id is nil' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, span, user_id: nil, user_exists: true)
        expect(span.tags).to_not include('appsec.events.users.login.failure.usr.id' => '42')
      end
    end

    it 'sets user existence on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, span, user_id: '42', user_exists: true)
        expect(span.tags).to include('appsec.events.users.login.failure.usr.exists' => 'true')
      end
    end

    it 'sets user non-existence  on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, span, user_id: '42', user_exists: false)
        expect(span.tags).to include('appsec.events.users.login.failure.usr.exists' => 'false')
      end
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, span, user_id: '42', user_exists: true, foo: 'bar')
        expect(span.tags).to include('appsec.events.users.login.failure.foo' => 'bar')
      end
    end
  end

  describe '#track_signup' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_signup(trace_op, span, user_id: '42')
        expect(span.tags).to include('appsec.events.users.signup.track' => 'true')
        expect(span.tags).to include('_dd.appsec.events.users.signup.auto.mode' => auto_mode)
      end
    end

    it 'sets successful user id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_signup(trace_op, span, user_id: '42')
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_signup(trace_op, span, user_id: '42', foo: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'appsec.events.users.signup.foo' => 'bar')
      end
    end

    it 'if user ID is nil do not set user tag' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_signup(trace_op, span, user_id: nil, foo: 'bar')
        expect(span.tags).to_not include('usr.id' => '42')
      end
    end
  end

  describe '#track' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track('foo', trace_op, span)
        expect(span.tags).to include('appsec.events.foo.track' => 'true')
        expect(span.tags).to include('_dd.appsec.events.foo.auto.mode' => auto_mode)
      end
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track('foo', trace_op, span, bar: 'baz')
        expect(span.tags).to include('appsec.events.foo.bar' => 'baz')
      end
    end
  end
end
