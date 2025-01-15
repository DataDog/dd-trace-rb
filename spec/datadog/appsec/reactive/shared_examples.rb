# frozen_string_literal: true

RSpec.shared_examples 'waf result' do
  context 'is a match' do
    it 'yields result and no blocking action' do
      waf_result = Datadog::AppSec::SecurityEngine::Result::Match.new(
        events: [], actions: [], derivatives: [], timeout: false, duration_ns: 0, duration_ext_ns: 0
      )

      expect(engine).to receive(:subscribe).and_call_original
      expect(appsec_context).to receive(:run_waf).and_return(waf_result)

      described_class.subscribe(engine, appsec_context) do |result|
        expect(result).to eq(waf_result)
      end
      expect(described_class.publish(engine, gateway)).to be_nil
    end

    it 'yields result and blocking action. The publish method catches the resul as well' do
      waf_result = Datadog::AppSec::SecurityEngine::Result::Match.new(
        events: [], actions: ['block'], derivatives: [], timeout: false, duration_ns: 0, duration_ext_ns: 0
      )

      expect(engine).to receive(:subscribe).and_call_original
      expect(appsec_context).to receive(:run_waf).and_return(waf_result)

      described_class.subscribe(engine, appsec_context) do |result|
        expect(result).to eq(waf_result)
      end
      expect(described_class.publish(engine, gateway)).to eq(true)
    end
  end

  context 'is ok' do
    let(:waf_result) do
      Datadog::AppSec::SecurityEngine::Result::Ok.new(
        events: [], actions: [], derivatives: [], timeout: false, duration_ns: 0, duration_ext_ns: 0
      )
    end

    it 'does not yield' do
      expect(engine).to receive(:subscribe).and_call_original
      expect(appsec_context).to receive(:run_waf).and_return(waf_result)
      expect { |b| described_class.subscribe(engine, appsec_context, &b) }.not_to yield_control

      expect(described_class.publish(engine, gateway)).to be_nil
    end
  end

  context 'is invalid_call' do
    let(:waf_result) do
      Datadog::AppSec::SecurityEngine::Result::Error.new(duration_ext_ns: 0)
    end

    it 'does not yield' do
      expect(engine).to receive(:subscribe).and_call_original
      expect(appsec_context).to receive(:run_waf).and_return(waf_result)
      expect { |b| described_class.subscribe(engine, appsec_context, &b) }.not_to yield_control

      expect(described_class.publish(engine, gateway)).to be_nil
    end
  end
end
