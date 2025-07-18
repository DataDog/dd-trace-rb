# frozen_string_literal: true

require 'spec_helper'
require 'datadog/kit/appsec/events/v2'

RSpec.describe Datadog::Kit::AppSec::Events::V2 do
  let(:sdk) { described_class }

  describe '#track_user_login_success' do
    context 'when AppSec context is active' do
      let(:context) { instance_double(Datadog::AppSec::Context, trace: trace, span: span) }
      let(:trace) { Datadog::Tracing::TraceOperation.new }
      let(:span) { trace.build_span('root') }

      before { allow(Datadog::AppSec).to receive(:active_context).and_return(context) }

      it 'raises exception when user key :id is missing' do
        expect { sdk.track_user_login_success('john.snow', {}) }
          .to raise_error(ArgumentError, 'missing required user key `:id`')
      end

      it 'raises exception when user key :id is not String' do
        expect { sdk.track_user_login_success('john.snow', {id: 15}) }
          .to raise_error(TypeError, 'user key `:id` must be a String')
      end

      it 'raises exception when user id argument is not string' do
        expect { sdk.track_user_login_success('john.snow', 15) }
          .to raise_error(TypeError, '`user_or_id` argument must be either String or Hash')
      end

      it 'raises exception when login argument is not string' do
        expect { sdk.track_user_login_success(12) }
          .to raise_error(TypeError, '`login` argument must be a String')
      end

      it 'raises exception when metadata argument is not Hash' do
        expect { sdk.track_user_login_success('john.snow', '42', 15) }
          .to raise_error(TypeError, '`metadata` argument must be a Hash')
      end

      it 'sets required tags on service entry span' do
        expect { sdk.track_user_login_success('john.snow') }
          .to change { span.tags }.to include(
            'appsec.events.users.login.success.usr.login' => 'john.snow',
            'appsec.events.users.login.success.track' => 'true',
            '_dd.appsec.events.users.login.success.sdk' => 'true',
          )

        expect(span.tags).not_to have_key('usr.login')
      end

      it 'sets additional user data as tags on service entry span' do
        expect { sdk.track_user_login_success('john.snow', '13') }
          .to change { span.tags }.to include(
            'usr.id' => '13',
            'usr.login' => 'john.snow',
            'appsec.events.users.login.success.usr.id' => '13',
            'appsec.events.users.login.success.usr.login' => 'john.snow',
            'appsec.events.users.login.success.track' => 'true',
            '_dd.appsec.user.collection_mode' => 'sdk',
            '_dd.appsec.events.users.login.success.sdk' => 'true',
          )
      end

      it 'sets metadata as tags on service entry span' do
        expect { sdk.track_user_login_success('john.snow', '13', hello: 'world') }
          .to change { span.tags }.to include(
            'usr.id' => '13',
            'usr.login' => 'john.snow',
            'appsec.events.users.login.success.usr.id' => '13',
            'appsec.events.users.login.success.usr.login' => 'john.snow',
            'appsec.events.users.login.success.hello' => 'world',
            'appsec.events.users.login.success.track' => 'true',
            '_dd.appsec.user.collection_mode' => 'sdk',
            '_dd.appsec.events.users.login.success.sdk' => 'true',
          )
      end

      it 'sets user login from argument and overrides it in user object' do
        expect { sdk.track_user_login_success('john.snow', {id: '13'}, login: 'john.wick') }
          .to change { span.tags }.to include(
            'usr.id' => '13',
            'usr.login' => 'john.snow',
            'appsec.events.users.login.success.usr.id' => '13',
            'appsec.events.users.login.success.usr.login' => 'john.snow',
            'appsec.events.users.login.success.track' => 'true',
            '_dd.appsec.user.collection_mode' => 'sdk',
            '_dd.appsec.events.users.login.success.sdk' => 'true',
          )
      end

      it 'sets user id from argument and ignores it in metadata' do
        expect { sdk.track_user_login_success('john.snow', '42', "usr.id": '13') }
          .to change { span.tags }.to include(
            'usr.id' => '42',
            'appsec.events.users.login.success.usr.id' => '42'
          )
      end

      it 'sets user login from argument and ignores it in metadata' do
        expect { sdk.track_user_login_success('john.snow', '42', "usr.login": 'john.doe') }
          .to change { span.tags }.to include(
            'usr.login' => 'john.snow',
            'appsec.events.users.login.success.usr.login' => 'john.snow'
          )
      end

      it 'sets track to true even if metadata track key is false' do
        expect { sdk.track_user_login_success('john.snow', '42', track: 'false') }
          .to change { span.tags }.to include(
            'appsec.events.users.login.success.track' => 'true',
          )
      end

      context 'when telemetry is available' do
        before do
          allow(Datadog).to receive(:components).and_return(components)
          allow(components).to receive(:telemetry).and_return(telemetry)
        end

        let(:components) { instance_double(Datadog::Core::Configuration::Components) }
        let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

        it 'record telemetry metrics' do
          expect(telemetry).to receive(:inc)
            .with('appsec', 'sdk.event', 1, tags: {event_type: 'login_success', sdk_version: 'v2'})

          sdk.track_user_login_success('john.snow')
        end
      end

      context 'when telemetry is not available' do
        before do
          allow(Datadog).to receive(:components).and_return(components)
          allow(components).to receive(:telemetry).and_return(nil)
          allow(components).to receive(:logger).and_return(logger)
        end

        let(:logger) { instance_double(Logger) }
        let(:components) { instance_double(Datadog::Core::Configuration::Components) }

        it 'does not record telemetry metrics' do
          expect(logger).to receive(:debug).with(/Telemetry component is unavailable/)

          sdk.track_user_login_success('john.snow')
        end
      end
    end
  end

  describe '#track_user_login_failure' do
    context 'when AppSec context is active' do
      let(:context) { instance_double(Datadog::AppSec::Context, trace: trace, span: span) }
      let(:trace) { Datadog::Tracing::TraceOperation.new }
      let(:span) { trace.build_span('root') }

      before { allow(Datadog::AppSec).to receive(:active_context).and_return(context) }

      it 'raises exception if exists argument is not a boolean' do
        expect { sdk.track_user_login_failure('john.snow', 'true') }
          .to raise_error(TypeError, '`user_exists` argument must be a boolean')

        expect { sdk.track_user_login_failure('john.snow', 1) }
          .to raise_error(TypeError, '`user_exists` argument must be a boolean')
      end

      it 'raises exception when login argument is not string' do
        expect { sdk.track_user_login_failure(12) }
          .to raise_error(TypeError, '`login` argument must be a String')
      end

      it 'raises exception when metadata argument is not Hash' do
        expect { sdk.track_user_login_failure('john.snow', true, 15) }
          .to raise_error(TypeError, '`metadata` argument must be a Hash')
      end

      it 'sets user existance to false when it is not provided' do
        expect { sdk.track_user_login_failure('john.snow') }
          .to change { span.tags }.to include(
            'appsec.events.users.login.failure.usr.login' => 'john.snow',
            'appsec.events.users.login.failure.usr.exists' => 'false',
            'appsec.events.users.login.failure.track' => 'true',
            '_dd.appsec.events.users.login.failure.sdk' => 'true',
          )
      end

      it 'sets metadata as tags on service entry span' do
        expect { sdk.track_user_login_failure('john.snow', true, hello: 'world') }
          .to change { span.tags }.to include(
            'appsec.events.users.login.failure.usr.login' => 'john.snow',
            'appsec.events.users.login.failure.usr.exists' => 'true',
            'appsec.events.users.login.failure.hello' => 'world',
            'appsec.events.users.login.failure.track' => 'true',
            '_dd.appsec.events.users.login.failure.sdk' => 'true',
          )
      end

      it 'sets id from argument and ignores it in metadata' do
        expect { sdk.track_user_login_failure('john.snow', false, "usr.id": 'john.doe') }
          .to change { span.tags }.to include(
            'appsec.events.users.login.failure.usr.login' => 'john.snow',
          )
      end

      it 'sets track to true even if metadata track key is false' do
        expect { sdk.track_user_login_failure('john.snow', false, track: 'false') }
          .to change { span.tags }.to include(
            'appsec.events.users.login.failure.track' => 'true',
          )
      end

      it 'sets exists from argument even if metadata exists key is false' do
        expect { sdk.track_user_login_failure('john.snow', false, "usr.exists": 'true') }
          .to change { span.tags }.to include(
            'appsec.events.users.login.failure.usr.exists' => 'false',
          )
      end

      context 'when telemetry is available' do
        before do
          allow(Datadog).to receive(:components).and_return(components)
          allow(components).to receive(:telemetry).and_return(telemetry)
        end

        let(:components) { instance_double(Datadog::Core::Configuration::Components) }
        let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

        it 'record telemetry metrics' do
          expect(telemetry).to receive(:inc)
            .with('appsec', 'sdk.event', 1, tags: {event_type: 'login_failure', sdk_version: 'v2'})

          sdk.track_user_login_failure('john.snow')
        end
      end

      context 'when telemetry is not available' do
        before do
          allow(Datadog).to receive(:components).and_return(components)
          allow(components).to receive(:telemetry).and_return(nil)
          allow(components).to receive(:logger).and_return(logger)
        end

        let(:logger) { instance_double(Logger) }
        let(:components) { instance_double(Datadog::Core::Configuration::Components) }

        it 'does not record telemetry metrics' do
          expect(logger).to receive(:debug).with(/Telemetry component is unavailable/)

          sdk.track_user_login_failure('john.snow')
        end
      end
    end
  end
end
