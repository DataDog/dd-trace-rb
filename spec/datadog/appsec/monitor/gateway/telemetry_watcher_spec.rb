# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/monitor/gateway/telemetry_watcher'

RSpec.describe Datadog::AppSec::Monitor::Gateway::TelemetryWatcher do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  before do
    allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
    allow(telemetry).to receive(:inc)
    allow(Datadog::AppSec).to receive(:active_context)

    described_class.watch_user_lifecycle_telemetry(gateway)
  end

  describe '.watch_user_lifecycle_telemetry' do
    it 'does not send telemetry when both user_id and user_login are present' do
      lifecycle_event = {
        event: 'users.login.success', has_user_id: true, has_user_login: true, framework: 'devise'
      }

      gateway.push('appsec.events.user_lifecycle', lifecycle_event)

      expect(telemetry).not_to have_received(:inc)
    end

    it 'does not send telemetry when user_login is present and user_id is missing' do
      lifecycle_event = {
        event: 'users.login.failure', has_user_id: false, has_user_login: true, framework: 'devise'
      }

      gateway.push('appsec.events.user_lifecycle', lifecycle_event)

      expect(telemetry).not_to have_received(:inc)
    end

    it 'sends missing_user_login telemetry when user_login is missing' do
      lifecycle_event = {
        event: 'users.authenticated_request', has_user_id: true, has_user_login: false, framework: 'devise'
      }

      gateway.push('appsec.events.user_lifecycle', lifecycle_event)

      expect(telemetry).to have_received(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_login', 1,
        tags: {event_type: 'authenticated_request', framework: 'devise'}
      )
      expect(telemetry).not_to have_received(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_id', 1,
        tags: anything
      )
    end

    it 'sends both missing_user_login and missing_user_id telemetry when both are missing' do
      lifecycle_event = {
        event: 'users.login.failure', has_user_id: false, has_user_login: false, framework: 'devise'
      }

      gateway.push('appsec.events.user_lifecycle', lifecycle_event)

      expect(telemetry).to have_received(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_login', 1,
        tags: {event_type: 'login_failure', framework: 'devise'}
      )
      expect(telemetry).to have_received(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_id', 1,
        tags: {event_type: 'login_failure', framework: 'devise'}
      )
    end

    it 'does not send telemetry for unknown event types' do
      lifecycle_event = {
        event: 'users.unknown_event', has_user_id: false, has_user_login: false, framework: 'devise'
      }

      gateway.push('appsec.events.user_lifecycle', lifecycle_event)

      expect(telemetry).not_to have_received(:inc)
    end
  end
end
