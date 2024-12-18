# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/engine'
require 'datadog/appsec/monitor/reactive/set_user'
require 'datadog/appsec/reactive/shared_examples'

RSpec.describe Datadog::AppSec::Monitor::Reactive::SetUser do
  let(:engine) { Datadog::AppSec::Reactive::Engine.new }
  let(:user) { double(:user, id: 1) }

  describe '.publish' do
    it 'propagates request body attributes to the engine' do
      expect(engine).to receive(:publish).with('usr.id', 1)

      described_class.publish(engine, user)
    end
  end

  describe '.subscribe' do
    let(:waf_context) { double(:waf_context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(engine).to receive(:subscribe).with('usr.id').and_call_original
        expect(waf_context).to_not receive(:run)
        described_class.subscribe(engine, waf_context)
      end
    end

    context 'all addresses have been published' do
      it 'does call the waf context with the right arguments' do
        expect(engine).to receive(:subscribe).and_call_original

        expected_waf_persisted_data = { 'usr.id' => 1 }

        waf_result = double(:waf_result, status: :ok, timeout: false)
        expect(waf_context).to receive(:run).with(
          expected_waf_persisted_data,
          {},
          Datadog.configuration.appsec.waf_timeout
        ).and_return(waf_result)
        described_class.subscribe(engine, waf_context)
        result = described_class.publish(engine, user)
        expect(result).to be_nil
      end
    end

    it_behaves_like 'waf result' do
      let(:gateway) { user }
    end
  end
end
