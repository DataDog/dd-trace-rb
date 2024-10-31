# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/operation'
require 'datadog/appsec/monitor/reactive/set_user'
require 'datadog/appsec/reactive/shared_examples'

RSpec.describe Datadog::AppSec::Monitor::Reactive::SetUser do
  let(:operation) { Datadog::AppSec::Reactive::Operation.new('test') }
  let(:user) { double(:user, id: 1) }

  describe '.publish' do
    it 'propagates request body attributes to the operation' do
      expect(operation).to receive(:publish).with('usr.id', 1)

      described_class.publish(operation, user)
    end
  end

  describe '.subscribe' do
    let(:waf_context) { double(:waf_context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(operation).to receive(:subscribe).with('usr.id').and_call_original
        expect(waf_context).to_not receive(:run)
        described_class.subscribe(operation, waf_context)
      end
    end

    context 'all addresses have been published' do
      it 'does call the waf context with the right arguments' do
        expect(operation).to receive(:subscribe).and_call_original

        expected_waf_persisted_data = { 'usr.id' => 1 }

        waf_result = double(:waf_result, status: :ok, timeout: false)
        expect(waf_context).to receive(:run).with(
          expected_waf_persisted_data,
          {},
          Datadog.configuration.appsec.waf_timeout
        ).and_return(waf_result)
        described_class.subscribe(operation, waf_context)
        result = described_class.publish(operation, user)
        expect(result).to be_nil
      end
    end

    it_behaves_like 'waf result' do
      let(:gateway) { user }
    end
  end
end
