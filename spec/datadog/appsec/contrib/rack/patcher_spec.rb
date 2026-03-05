# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rack/patcher'

RSpec.describe Datadog::AppSec::Contrib::Rack::Patcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }
  let(:middlewares) { gateway.instance_variable_get(:@middlewares) }

  before do
    described_class.instance_variable_set(:@patched, false)
    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)

    Datadog.configure do |c|
      c.appsec.enabled = true
    end
  end

  after do
    described_class.instance_variable_set(:@patched, false)
    Datadog.configuration.reset!
  end

  describe '.patch' do
    context 'when called twice via instrument' do
      it 'does not register gateway watchers twice' do
        Datadog.configuration.appsec.instrument :rack

        expect { Datadog.configuration.appsec.instrument :rack }.not_to change {
          middlewares.transform_values(&:size)
        }
      end
    end
  end
end
