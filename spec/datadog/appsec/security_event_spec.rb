# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/security_event'

RSpec.describe Datadog::AppSec::SecurityEvent do
  let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:span) { instance_double(Datadog::Tracing::SpanOperation) }

  describe '#keep?' do
    context 'when WAF result is a keep' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
          events: [], actions: {}, attributes: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0,
          keep: true, input_truncated: false
        )
      end

      it { expect(event).to be_keep }
    end

    context 'when WAF result is a no keep' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, attributes: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0,
          keep: false, input_truncated: false
        )
      end

      it { expect(event).not_to be_keep }
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
    context 'when WAF result contains schema attributes' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [],
          actions: {},
          attributes: {'_dd.appsec.s.req.headers' => [{'host' => [8], 'version' => [8]}]},
          keep: false,
          timeout: false,
          duration_ns: 0,
          duration_ext_ns: 0,
          input_truncated: false
        )
      end

      it { expect(event).to be_schema }
    end

    context 'when WAF result does not contain schema attributes' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [],
          actions: {},
          attributes: {'not_schema' => 'value'},
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
    context 'when WAF result contains fingerprint attributes' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [],
          actions: {},
          attributes: {'_dd.appsec.fp.http.endpoint' => 'http-post-c1525143-2d711642-'},
          keep: false,
          timeout: false,
          duration_ns: 0,
          duration_ext_ns: 0,
          input_truncated: false
        )
      end

      it { expect(event).to be_fingerprint }
    end

    context 'when WAF result does not contain fingerprint attributes' do
      subject(:event) { described_class.new(waf_result, trace: trace, span: span) }

      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [],
          actions: {},
          attributes: {'not_fingerprint' => 'value'},
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
