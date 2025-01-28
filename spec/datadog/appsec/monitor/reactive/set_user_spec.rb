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
    let(:appsec_context) { instance_double(Datadog::AppSec::Context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(engine).to receive(:subscribe).with('usr.id').and_call_original
        expect(appsec_context).to_not receive(:run_waf)
        described_class.subscribe(engine, appsec_context)
      end
    end

    context 'all addresses have been published' do
      let(:waf_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it 'does call the waf context with the right arguments' do
        expect(engine).to receive(:subscribe).and_call_original
        expect(appsec_context).to receive(:run_waf)
          .with({ 'usr.id' => 1 }, {}, Datadog.configuration.appsec.waf_timeout)
          .and_return(waf_result)

        described_class.subscribe(engine, appsec_context)
        expect(described_class.publish(engine, user)).to be_nil
      end
    end

    it_behaves_like 'waf result' do
      let(:gateway) { user }
    end
  end
end
