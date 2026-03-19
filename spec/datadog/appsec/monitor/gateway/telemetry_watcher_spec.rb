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

  describe '.watch_user_lifecycle' do
    before { described_class.watch_user_lifecycle(gateway) }

    %w[
      identity.devise.login_success
      identity.devise.login_failure
      identity.devise.signup
    ].each do |event_name|
      _, framework, event_type = event_name.split('.')

      context "with #{event_name}" do
        it 'reports missing_user_login when login is nil' do
          expect(telemetry).to receive(:inc).with(
            'appsec', 'instrum.user_auth.missing_user_login', 1,
            tags: {framework: framework, event_type: event_type},
          )

          gateway.push(event_name, {id: '123'})
        end

        it 'reports both metrics when login and id are nil' do
          expect(telemetry).to receive(:inc).with(
            'appsec', 'instrum.user_auth.missing_user_login', 1,
            tags: {framework: framework, event_type: event_type},
          )
          expect(telemetry).to receive(:inc).with(
            'appsec', 'instrum.user_auth.missing_user_id', 1,
            tags: {framework: framework, event_type: event_type},
          )

          gateway.push(event_name, {})
        end

        it 'does not report any telemetry when login is present' do
          expect(telemetry).not_to receive(:inc)

          gateway.push(event_name, {login: 'alice'})
        end
      end
    end
  end

  describe '.watch_authenticated_request' do
    before { described_class.watch_authenticated_request(gateway) }

    it 'reports missing_user_id when id is nil' do
      expect(telemetry).to receive(:inc).with(
        'appsec', 'instrum.user_auth.missing_user_id', 1,
        tags: {framework: 'devise', event_type: 'authenticated_request'},
      )

      gateway.push('identity.devise.authenticated_request', {})
    end

    it 'does not report missing_user_login even when login is nil' do
      expect(telemetry).not_to receive(:inc).with(
        'appsec', 'instrum.user_auth.missing_user_login', anything, anything,
      )

      gateway.push('identity.devise.authenticated_request', {})
    end

    it 'does not report any telemetry when id is present' do
      expect(telemetry).not_to receive(:inc)

      gateway.push('identity.devise.authenticated_request', {id: '123'})
    end
  end
end
