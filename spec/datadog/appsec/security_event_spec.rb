# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/security_event'

RSpec.describe Datadog::AppSec::SecurityEvent do
  let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:span) { instance_double(Datadog::Tracing::SpanOperation) }

  describe '#attack?' do
    context 'when WAF result is a match' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
<<<<<<< HEAD
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0,
          input_truncated: false
=======
          events: [], actions: {}, derivatives: {}, keep: false, timeout: false, duration_ns: 0, duration_ext_ns: 0
>>>>>>> c0440f8c37 (Bump libddwaf version to 1.25.1.0.0)
        )
      end

      it { expect(event).to be_attack }
    end

    context 'when WAF result is an ok' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
<<<<<<< HEAD
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0,
          input_truncated: false
=======
          events: [], actions: {}, derivatives: {}, keep: false, timeout: false, duration_ns: 0, duration_ext_ns: 0
>>>>>>> c0440f8c37 (Bump libddwaf version to 1.25.1.0.0)
        )
      end

      it { expect(event).not_to be_attack }
    end

    context 'when WAF result is an error' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }
      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Error.new(duration_ext_ns: 0, input_truncated: false)
      end

      it { expect(event).not_to be_attack }
    end
  end

  describe '#schema?' do
    context 'when WAF result contains schema derivatives' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [],
          actions: {},
          derivatives: {'_dd.appsec.s.req.headers' => [{'host' => [8], 'version' => [8]}]},
          keep: false,
          timeout: false,
          duration_ns: 0,
          duration_ext_ns: 0,
          input_truncated: false
        )
      end

      it { expect(event).to be_schema }
    end

    context 'when WAF result does not contain schema derivatives' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [],
          actions: {},
          derivatives: {'not_schema' => 'value'},
          keep: false,
          timeout: false,
          duration_ns: 0,
          duration_ext_ns: 0,
          input_truncated: false
        )
      end

      it { expect(event).not_to be_schema }
    end
  end

  describe '#fingerprint?' do
    context 'when WAF result contains fingerprint derivatives' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [],
          actions: {},
          derivatives: {'_dd.appsec.fp.http.endpoint' => 'http-post-c1525143-2d711642-'},
          keep: false,
          timeout: false,
          duration_ns: 0,
          duration_ext_ns: 0,
          input_truncated: false
        )
      end

      it { expect(event).to be_fingerprint }
    end

    context 'when WAF result does not contain fingerprint derivatives' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [],
          actions: {},
          derivatives: {'not_fingerprint' => 'value'},
          keep: false,
          timeout: false,
          duration_ns: 0,
          duration_ext_ns: 0,
          input_truncated: false
        )
      end

      it { expect(event).not_to be_fingerprint }
    end
  end
end
