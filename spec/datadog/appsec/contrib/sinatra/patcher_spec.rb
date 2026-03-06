# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'sinatra'
require 'datadog/appsec/contrib/sinatra/patcher'

RSpec.describe Datadog::AppSec::Contrib::Sinatra::Patcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }
  let(:middlewares) { gateway.instance_variable_get(:@middlewares) }

  before do
    @original_patched = described_class.instance_variable_get(:@patched)
    described_class.instance_variable_set(:@patched, false)
    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)

    Datadog.configure do |c|
      c.appsec.enabled = true
    end
  end

  after do
    described_class.instance_variable_set(:@patched, @original_patched)
    Datadog.configuration.reset!
  end

  describe '.patch' do
    context 'when called twice via instrument' do
      it 'does not register gateway watchers twice' do
        Datadog.configuration.appsec.instrument :sinatra

        expect { Datadog.configuration.appsec.instrument :sinatra }.not_to change {
          middlewares.transform_values(&:size)
        }
      end
    end
  end
end
