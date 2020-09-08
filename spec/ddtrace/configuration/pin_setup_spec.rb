require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configuration::PinSetup do
  let(:target) { Object.new }

  before(:each) do
    Datadog::Pin.new('original-service', app: 'original-app').onto(target)
  end

  describe '#call' do
    before(:each) { described_class.new(target, options).call }

    context 'given options' do
      let(:options) do
        {
          service_name: 'my-service',
          app: 'my-app',
          app_type: :cache,
          tags: { env: :prod },
          tracer: 'deprecated option',
          distributed_tracing: true
        }
      end

      it do
        expect(target.datadog_pin.service).to eq('my-service')
        expect(target.datadog_pin.app).to eq('my-app')
        expect(target.datadog_pin.tags).to eq(env: :prod)
        expect(target.datadog_pin.config).to eq(distributed_tracing: true)
        expect(target.datadog_pin.tracer).to eq(Datadog.tracer)
      end
    end

    context 'missing options' do
      let(:options) { { app: 'custom-app' } }

      it do
        expect(target.datadog_pin.app).to eq('custom-app')
        expect(target.datadog_pin.service).to eq('original-service')
      end
    end
  end

  describe 'Datadog#configure' do
    before(:each) { Datadog.configure(target, service_name: :foo, extra: :bar) }

    it do
      expect(target.datadog_pin.service).to eq(:foo)
      expect(target.datadog_pin.config).to eq(extra: :bar)
    end
  end
end
