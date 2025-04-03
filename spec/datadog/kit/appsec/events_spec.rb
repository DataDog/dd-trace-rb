# frozen_string_literal: true

require 'spec_helper'

require 'datadog/tracing/trace_operation'
require 'datadog/kit/appsec/events'

RSpec.describe Datadog::Kit::AppSec::Events do
  let(:trace_op) { Datadog::Tracing::TraceOperation.new }

  shared_context 'uses AppSec context' do
    before do
      allow(processor).to receive(:new_runner).and_return(instance_double(Datadog::AppSec::SecurityEngine::Runner))
      allow(Datadog::AppSec).to receive(:active_context).and_return(appsec_active_context)
    end

    let(:processor) { instance_double(Datadog::AppSec::Processor) }
    let(:appsec_span) { trace_op.build_span('root') }

    context 'when is present' do
      let(:appsec_active_context) { Datadog::AppSec::Context.new(trace_op, appsec_span, processor) }

      it 'sets tags on AppSec span' do
        event
        expect(appsec_span.has_tag?(event_tag)).to eq true
      end
    end

    context 'when is not present' do
      let(:appsec_active_context) { nil }

      it 'sets tags on active_span' do
        trace_op.measure('root') do |span, _trace|
          event
          expect(span.has_tag?(event_tag)).to eq true
        end
        expect(appsec_span.has_tag?(event_tag)).to eq false
      end
    end
  end

  shared_examples 'when tracing disabled' do
    it 'does mark trace for keeping' do
      expect(Datadog::Tracing.active_trace).to_not receive(:keep!)
      expect do
        event
      end.to_not raise_error
    end
  end

  describe '#track_login_success' do
    it 'sets additional user login data based on user id as tags' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_login_success(trace_op, user: { id: '42' }) }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => '42',
            'appsec.events.users.login.success.usr.login' => '42'
          )
      end
    end

    it 'sets additional user login data from other keys as tags' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_login_success(trace_op, user: { id: '42' }, 'usr.login': 'hey') }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => 'hey',
            'appsec.events.users.login.success.usr.login' => 'hey'
          )
      end
    end

    it 'sets additional user login data as tags' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_login_success(trace_op, user: { id: '42', login: 'hey' }) }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => 'hey',
            'appsec.events.users.login.success.usr.login' => 'hey'
          )
      end
    end

    it 'sets additional user login data as tags with user data priority' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_login_success(trace_op, user: { id: '42', login: 'hey' }, 'usr.login': 'extra') }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => 'hey',
            'appsec.events.users.login.success.usr.login' => 'hey'
          )
      end
    end

    it 'sets additional user login data from other string keys as tags', ruby: '>= 2.7' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_login_success(trace_op, user: { id: '42' }, 'usr.login' => 'hey') }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => 'hey',
            'appsec.events.users.login.success.usr.login' => 'hey'
          )
      end
    end

    it 'sets event tracking key on trace' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_login_success(trace_op, user: { id: '42' }) }
          .to change { span.tags }.to include(
            'appsec.events.users.login.success.track' => 'true',
            '_dd.appsec.events.users.login.success.sdk' => 'true'
          )
      end
    end

    it 'sets successful user id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_success(trace_op, user: { id: '42' })
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_success(trace_op, user: { id: '42' }, foo: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'appsec.events.users.login.success.foo' => 'bar')
      end
    end

    it 'sets user login from user id' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_success(trace_op, user: { id: '42' })
        expect(span.tags).to include(
          'appsec.events.users.login.success.track' => 'true',
          'appsec.events.users.login.success.usr.login' => '42',
          '_dd.appsec.events.users.login.success.sdk' => 'true'
        )
      end
    end

    it 'sets user login from given user login' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_success(trace_op, user: { id: '42', login: 'test-42' })
        expect(span.tags).to include(
          'appsec.events.users.login.success.track' => 'true',
          'appsec.events.users.login.success.usr.login' => 'test-42',
          '_dd.appsec.events.users.login.success.sdk' => 'true'
        )
      end
    end

    it 'raises ArgumentError is user ID is nil' do
      expect do
        trace_op.measure('root') do |_span, _trace|
          described_class.track_login_success(trace_op, user: { id: nil }, foo: 'bar')
        end
      end.to raise_error(ArgumentError)
    end

    it 'maintains integrity of user argument' do
      user_argument = { id: '42' }
      user_argument_dup = user_argument.dup
      trace_op.measure('root') do |_span, _trace|
        described_class.track_login_success(trace_op, user: user_argument, foo: 'bar')
      end
      expect(user_argument).to eql(user_argument_dup)
    end

    it_behaves_like 'uses AppSec context' do
      let(:event_tag) { 'appsec.events.users.login.success.track' }
      subject(:event) { described_class.track_login_success(trace_op, user: { id: '42' }) }
    end

    it_behaves_like 'when tracing disabled' do
      subject(:event) { described_class.track_login_success(user: { id: '42' }) }
    end
  end

  describe '#track_login_failure' do
    it 'sets additional user login data based on user id as tags' do
      trace_op.measure('root') do |span, _trace|
        expect { described_class.track_login_failure(trace_op, user_id: '42', user_exists: true) }
          .to change { span.tags }.to include('appsec.events.users.login.failure.usr.login' => '42')
      end
    end

    it 'sets additional user login data from other keys as tags' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_login_failure(trace_op, user_id: '42', user_exists: true, 'usr.login': 'hey') }
          .to change { span.tags }.to include('appsec.events.users.login.failure.usr.login' => 'hey')
      end
    end

    it 'sets additional user login data from other string keys as tags', ruby: '>= 2.7' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_login_failure(trace_op, user_id: '42', user_exists: true, 'usr.login' => 'hey') }
          .to change { span.tags }.to include('appsec.events.users.login.failure.usr.login' => 'hey')
      end
    end

    it 'sets event tracking key on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)
        expect(span.tags).to include('appsec.events.users.login.failure.track' => 'true')
        expect(span.tags).to include('_dd.appsec.events.users.login.failure.sdk' => 'true')
      end
    end

    it 'sets failing user id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)
        expect(span.tags).to include('appsec.events.users.login.failure.usr.id' => '42')
      end
    end

    it 'sets user existence on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)
        expect(span.tags).to include('appsec.events.users.login.failure.usr.exists' => 'true')
      end
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_login_failure(trace_op, user_id: '42', user_exists: true, foo: 'bar')
        expect(span.tags).to include('appsec.events.users.login.failure.foo' => 'bar')
      end
    end

    context 'when user does not exist' do
      it 'sets user non-existence on trace' do
        trace_op.measure('root') do |span, _trace|
          described_class.track_login_failure(trace_op, user_exists: false)
          expect(span.tags).to include('appsec.events.users.login.failure.usr.exists' => 'false')
        end
      end

      it 'does not set user id on trace' do
        trace_op.measure('root') do |span, _trace|
          described_class.track_login_failure(trace_op, user_exists: false)
          expect(span.tags).not_to have_key('appsec.events.users.login.failure.usr.id')
        end
      end

      it 'sets user login to user id' do
        trace_op.measure('root') do |span, _trace|
          described_class.track_login_failure(trace_op, user_id: '42', user_exists: true)

          expect(span.tags).to include('appsec.events.users.login.failure.usr.login' => '42')
        end
      end

      it 'sets user login to given login' do
        trace_op.measure('root') do |span, _trace|
          described_class.track_login_failure(trace_op, user_id: '42', user_exists: true, 'usr.login': 'test-42')

          expect(span.tags).to include('appsec.events.users.login.failure.usr.login' => 'test-42')
        end
      end
    end

    it_behaves_like 'uses AppSec context' do
      let(:event_tag) { 'appsec.events.users.login.failure.track' }
      subject(:event) { described_class.track_login_failure(trace_op, user_id: '42', user_exists: true) }
    end

    it_behaves_like 'when tracing disabled' do
      subject(:event) { described_class.track_login_failure(user_id: '42', user_exists: true) }
    end
  end

  describe '#track_signup' do
    it 'sets additional user login data based on user id as tags' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_signup(trace_op, user: { id: '42' }) }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => '42',
            'appsec.events.users.signup.usr.login' => '42'
          )
      end
    end

    it 'sets additional user login data as tags' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_signup(trace_op, user: { id: '42', login: 'hey' }) }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => 'hey',
            'appsec.events.users.signup.usr.login' => 'hey'
          )
      end
    end

    it 'sets additional user login data from other keys as tags' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_signup(trace_op, user: { id: '42' }, 'usr.login': 'hey') }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => 'hey',
            'appsec.events.users.signup.usr.login' => 'hey'
          )
      end
    end

    it 'sets additional user login data from other string keys as tags', ruby: '>= 2.7' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_signup(trace_op, user: { id: '42' }, 'usr.login' => 'hey') }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => 'hey',
            'appsec.events.users.signup.usr.login' => 'hey'
          )
      end
    end

    it 'sets additional user login data as tags with user data priority' do
      trace_op.measure('root') do |span, _|
        expect { described_class.track_signup(trace_op, user: { id: '42', login: 'hey' }, 'usr.login': 'extra') }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'usr.login' => 'hey',
            'appsec.events.users.signup.usr.login' => 'hey'
          )
      end
    end

    it 'sets event tracking key on trace' do
      trace_op.measure('root') do |span, _trace|
        expect { described_class.track_signup(trace_op, user: { id: '42' }) }
          .to change { span.tags }.to include(
            'appsec.events.users.signup.track' => 'true',
            '_dd.appsec.events.users.signup.sdk' => 'true'
          )
      end
    end

    it 'sets successful user id on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_signup(trace_op, user: { id: '42' })
        expect(span.tags).to include('usr.id' => '42')
      end
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track_signup(trace_op, user: { id: '42' }, foo: 'bar')
        expect(span.tags).to include('usr.id' => '42', 'appsec.events.users.signup.foo' => 'bar')
      end
    end

    it 'raises ArgumentError is user ID is nil' do
      expect do
        trace_op.measure('root') do
          described_class.track_signup(trace_op, user: { id: nil }, foo: 'bar')
        end
      end.to raise_error(ArgumentError)
    end

    it 'maintains integrity of user argument' do
      user_argument = { id: '42' }
      user_argument_dup = user_argument.dup
      trace_op.measure('root') do |_span, _trace|
        described_class.track_signup(trace_op, user: user_argument, foo: 'bar')
      end
      expect(user_argument).to eql(user_argument_dup)
    end

    it_behaves_like 'uses AppSec context' do
      let(:event_tag) { 'appsec.events.users.signup.track' }
      subject(:event) { described_class.track_signup(trace_op, user: { id: '42' }, foo: 'bar') }
    end

    it_behaves_like 'when tracing disabled' do
      subject(:event) { described_class.track_signup(user: { id: '42' }, foo: 'bar') }
    end
  end

  describe '#track' do
    it 'sets event tracking key on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track('foo', trace_op)
        expect(span.tags).to include('appsec.events.foo.track' => 'true')
        expect(span.tags).to include('_dd.appsec.events.foo.sdk' => 'true')
      end
    end

    it 'sets other keys on trace' do
      trace_op.measure('root') do |span, _trace|
        described_class.track('foo', trace_op, bar: 'baz')
        expect(span.tags).to include('appsec.events.foo.bar' => 'baz')
      end
    end

    it_behaves_like 'uses AppSec context' do
      let(:event_tag) { 'appsec.events.foo.track' }
      subject(:event) { described_class.track('foo', trace_op) }
    end

    it_behaves_like 'when tracing disabled' do
      subject(:event) { described_class.track('foo') }
    end
  end
end
