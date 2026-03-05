# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'faraday'
require 'datadog/appsec/contrib/faraday/patcher'

RSpec.describe Datadog::AppSec::Contrib::Faraday::Patcher do
  before do
    described_class.instance_variable_set(:@patched, false)

    Datadog.configure do |c|
      c.appsec.enabled = true
    end
  end

  after do
    Datadog.configuration.reset!
  end

  describe '.patch' do
    context 'when called twice via instrument' do
      it 'does not add SSRFDetectionMiddleware to default connection twice' do
        Datadog.configuration.appsec.instrument :faraday

        expect { Datadog.configuration.appsec.instrument :faraday }.not_to change {
          ::Faraday.default_connection.builder.handlers.count(
            Datadog::AppSec::Contrib::Faraday::SSRFDetectionMiddleware
          )
        }
      end
    end
  end
end
