# frozen_string_literal: true

RSpec.shared_examples 'waf result' do
  context 'is a match' do
    it 'yields result and no blocking action' do
      expect(engine).to receive(:subscribe).and_call_original

      waf_result = double(:waf_result, status: :match, timeout: false, actions: [])
      expect(waf_context).to receive(:run).and_return(waf_result)
      described_class.subscribe(engine, waf_context) do |result|
        expect(result).to eq(waf_result)
      end
      result = described_class.publish(engine, gateway)
      expect(result).to be_nil
    end

    it 'yields result and blocking action. The publish method catches the resul as well' do
      expect(engine).to receive(:subscribe).and_call_original

      waf_result = double(:waf_result, status: :match, timeout: false, actions: ['block'])
      expect(waf_context).to receive(:run).and_return(waf_result)
      described_class.subscribe(engine, waf_context) do |result|
        expect(result).to eq(waf_result)
      end
      block = described_class.publish(engine, gateway)
      expect(block).to eq(true)
    end
  end

  context 'is ok' do
    it 'does not yield' do
      expect(engine).to receive(:subscribe).and_call_original

      waf_result = double(:waf_result, status: :ok, timeout: false)
      expect(waf_context).to receive(:run).and_return(waf_result)
      expect { |b| described_class.subscribe(engine, waf_context, &b) }.not_to yield_control
      result = described_class.publish(engine, gateway)
      expect(result).to be_nil
    end
  end

  context 'is invalid_call' do
    it 'does not yield' do
      expect(engine).to receive(:subscribe).and_call_original

      waf_result = double(:waf_result, status: :invalid_call, timeout: false)
      expect(waf_context).to receive(:run).and_return(waf_result)
      expect { |b| described_class.subscribe(engine, waf_context, &b) }.not_to yield_control
      result = described_class.publish(engine, gateway)
      expect(result).to be_nil
    end
  end

  context 'is invalid_rule' do
    it 'does not yield' do
      expect(engine).to receive(:subscribe).and_call_original

      waf_result = double(:waf_result, status: :invalid_rule, timeout: false)
      expect(waf_context).to receive(:run).and_return(waf_result)
      expect { |b| described_class.subscribe(engine, waf_context, &b) }.not_to yield_control
      result = described_class.publish(engine, gateway)
      expect(result).to be_nil
    end
  end

  context 'is invalid_flow' do
    it 'does not yield' do
      expect(engine).to receive(:subscribe).and_call_original

      waf_result = double(:waf_result, status: :invalid_flow, timeout: false)
      expect(waf_context).to receive(:run).and_return(waf_result)
      expect { |b| described_class.subscribe(engine, waf_context, &b) }.not_to yield_control
      result = described_class.publish(engine, gateway)
      expect(result).to be_nil
    end
  end

  context 'is no_rule' do
    it 'does not yield' do
      expect(engine).to receive(:subscribe).and_call_original

      waf_result = double(:waf_result, status: :no_rule, timeout: false)
      expect(waf_context).to receive(:run).and_return(waf_result)
      expect { |b| described_class.subscribe(engine, waf_context, &b) }.not_to yield_control
      result = described_class.publish(engine, gateway)
      expect(result).to be_nil
    end
  end

  context 'is unknown' do
    it 'does not yield' do
      expect(engine).to receive(:subscribe).and_call_original

      waf_result = double(:waf_result, status: :foo, timeout: false)
      expect(waf_context).to receive(:run).and_return(waf_result)
      expect { |b| described_class.subscribe(engine, waf_context, &b) }.not_to yield_control
      result = described_class.publish(engine, gateway)
      expect(result).to be_nil
    end
  end
end
