# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/monitor/gateway/telemetry_watcher'

RSpec.describe Datadog::AppSec::Monitor::Gateway::TelemetryWatcher do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  before do
    allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
    allow(telemetry).to receive(:inc)
  end

  describe '.watch_set_user' do
    before { described_class.watch_set_user(gateway) }

    %w[login_success signup].each do |event_type|
      context "with #{event_type} event_type" do
        it 'reports missing_user_login when login is nil' do
          expect(telemetry).to receive(:inc).with(
            'appsec', 'instrum.user_auth.missing_user_login', 1,
            tags: {framework: 'devise', event_type: event_type},
          )

          gateway.push('identity.set_user', {id: '123', framework: 'devise', event_type: event_type})
        end

        it 'reports both metrics when login and id are nil' do
          expect(telemetry).to receive(:inc).with(
            'appsec', 'instrum.user_auth.missing_user_login', 1,
            tags: {framework: 'devise', event_type: event_type},
          )
          expect(telemetry).to receive(:inc).with(
            'appsec', 'instrum.user_auth.missing_user_id', 1,
            tags: {framework: 'devise', event_type: event_type},
          )

          gateway.push('identity.set_user', {framework: 'devise', event_type: event_type})
        end

        it 'does not report any telemetry when login is present' do
          expect(telemetry).not_to receive(:inc)

          gateway.push('identity.set_user', {login: 'alice', framework: 'devise', event_type: event_type})
        end
      end
    end

    context 'with authenticated_request event_type' do
      it 'reports missing_user_id when id is nil' do
        expect(telemetry).to receive(:inc).with(
          'appsec', 'instrum.user_auth.missing_user_id', 1,
          tags: {framework: 'devise', event_type: 'authenticated_request'},
        )

        gateway.push('identity.set_user', {framework: 'devise', event_type: 'authenticated_request'})
      end

      it 'does not report missing_user_login even when login is nil' do
        expect(telemetry).not_to receive(:inc).with(
          'appsec', 'instrum.user_auth.missing_user_login', anything, anything,
        )

        gateway.push('identity.set_user', {framework: 'devise', event_type: 'authenticated_request'})
      end

      it 'does not report any telemetry when id is present' do
        expect(telemetry).not_to receive(:inc)

        gateway.push('identity.set_user', {id: '123', framework: 'devise', event_type: 'authenticated_request'})
      end
    end

    context 'when event_type is not set' do
      it 'does not report any telemetry' do
        expect(telemetry).not_to receive(:inc)

        gateway.push('identity.set_user', {id: '123', framework: 'sdk'})
      end
    end
  end

  describe '.watch_login_failure' do
    before { described_class.watch_login_failure(gateway) }

    it 'reports missing_user_login when login is nil' do
      expect(telemetry).to receive(:inc).with(
        'appsec', 'instrum.user_auth.missing_user_login', 1,
        tags: {framework: 'devise', event_type: 'login_failure'},
      )

      gateway.push('identity.login_failure', {id: '123', framework: 'devise'})
    end

    it 'reports both metrics when login and id are nil' do
      expect(telemetry).to receive(:inc).with(
        'appsec', 'instrum.user_auth.missing_user_login', 1,
        tags: {framework: 'devise', event_type: 'login_failure'},
      )
      expect(telemetry).to receive(:inc).with(
        'appsec', 'instrum.user_auth.missing_user_id', 1,
        tags: {framework: 'devise', event_type: 'login_failure'},
      )

      gateway.push('identity.login_failure', {framework: 'devise'})
    end

    it 'does not report any telemetry when login is present' do
      expect(telemetry).not_to receive(:inc)

      gateway.push('identity.login_failure', {login: 'alice', framework: 'devise'})
    end
  end
end
