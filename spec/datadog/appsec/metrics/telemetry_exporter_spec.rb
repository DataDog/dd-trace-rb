# frozen_string_literal: true

require 'libddwaf'

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/metrics/telemetry_exporter'

RSpec.describe Datadog::AppSec::Metrics::TelemetryExporter do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  before do
    allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
  end

  describe '.export_waf_request_metrics' do
    let(:context) do
      instance_double(
        Datadog::AppSec::Context,
        waf_runner_ruleset_version: '1.0.0',
        interrupted?: false,
        trace: trace
      )
    end

    let(:trace) { instance_double(Datadog::Tracing::TraceOperation, sampled?: true) }

    let(:waf_metrics) do
      Datadog::AppSec::Metrics::Collector::Store.new(
        evals: 0, matches: 0, errors: 0, timeouts: 0, duration_ns: 0, duration_ext_ns: 0,
        inputs_truncated: 0, downstream_requests: 0
      )
    end

    it 'exports all required tags via Telemetry' do
      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1, tags: {
          waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
          event_rules_version: '1.0.0',
          rule_triggered: 'false',
          waf_error: 'false',
          waf_timeout: 'false',
          request_blocked: 'false',
          block_failure: 'false',
          rate_limited: 'false',
          input_truncated: 'false'
        }
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets rule_triggered as "true" when metrics has non-zero count of matches' do
      waf_metrics.matches = 1

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(rule_triggered: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets waf_error as "true" when metrics has non-zero count of errors' do
      waf_metrics.errors = 1

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(waf_error: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets waf_timeout as "true" when metrics has non-zero count of timeouts' do
      waf_metrics.timeouts = 1

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(waf_timeout: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets input_truncated as "true" when metrics has non-zero count of input truncations' do
      waf_metrics.inputs_truncated = 1

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(input_truncated: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets request_blocked as "true" when context is interrupted' do
      allow(context).to receive(:interrupted?).and_return(true)

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(request_blocked: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets rate_limited as "true" when trace was not sampled' do
      allow(trace).to receive(:sampled?).and_return(false)

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(rate_limited: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end
  end

  describe '.export_api_security_metrics' do
    before { allow(telemetry).to receive(:inc) }

    let(:span) { Datadog::Tracing::SpanOperation.new('root') }
    let(:context) { instance_double(Datadog::AppSec::Context, state: {}, span: span) }

    it 'increases api_security.request.schema metric when schema was extracted' do
      expect(telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'api_security.request.schema', 1,
        tags: {framework: 'rails'}
      )

      context.state[:schema_extracted] = true
      context.state[:web_framework] = 'rails'
      described_class.export_api_security_metrics(context)
    end

    it 'increases api_security.request.no_schema metric when schema was not extracted' do
      expect(telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'api_security.request.no_schema', 1,
        tags: {framework: 'rails'}
      )

      context.state[:schema_extracted] = false
      context.state[:web_framework] = 'rails'
      described_class.export_api_security_metrics(context)
    end

    it 'does not export telemetry when web framework is nil' do
      expect(telemetry).not_to receive(:inc)

      context.state[:schema_extracted] = true
      described_class.export_api_security_metrics(context)
    end

    it 'increases api_security.missing_route metric when http.route tag is missing on the context span' do
      expect(telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'api_security.missing_route', 1,
        tags: {framework: 'rails'}
      )

      context.state[:web_framework] = 'rails'
      described_class.export_api_security_metrics(context)
    end

    it 'does not increase api_security.missing_route metric when http.route tag is present on the context span' do
      expect(telemetry).not_to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'api_security.missing_route', 1,
        tags: {framework: 'rails'}
      )

      span.set_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_ROUTE, '/foo')
      context.state[:web_framework] = 'rails'
      described_class.export_api_security_metrics(context)
    end
  end

  describe '.export_user_auth_metrics' do
    let(:context) { instance_double(Datadog::AppSec::Context, state: {}) }

    it 'does not export telemetry when user_auth is not set' do
      expect(telemetry).not_to receive(:inc)

      described_class.export_user_auth_metrics(context)
    end

    it 'does not export telemetry when both login and id are present' do
      expect(telemetry).not_to receive(:inc)

      context.state[:user_auth] = {id: '1', login: 'john@example.com', event: :login_success, framework: 'devise'}
      described_class.export_user_auth_metrics(context)
    end

    it 'does not export telemetry when login is present and id is nil' do
      expect(telemetry).not_to receive(:inc)

      context.state[:user_auth] = {id: nil, login: 'john@example.com', event: :login_failure, framework: 'devise'}
      described_class.export_user_auth_metrics(context)
    end

    it 'increases missing_user_login metric when login is nil' do
      expect(telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_login', 1,
        tags: {event_type: 'authenticated_request', framework: 'devise'}
      )

      context.state[:user_auth] = {id: '1', login: nil, event: :authenticated_request, framework: 'devise'}
      described_class.export_user_auth_metrics(context)
    end

    it 'increases both missing_user_login and missing_user_id metrics when both login and id are nil' do
      expect(telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_login', 1,
        tags: {event_type: 'login_failure', framework: 'devise'}
      )
      expect(telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_id', 1,
        tags: {event_type: 'login_failure', framework: 'devise'}
      )

      context.state[:user_auth] = {id: nil, login: nil, event: :login_failure, framework: 'devise'}
      described_class.export_user_auth_metrics(context)
    end
  end
end
