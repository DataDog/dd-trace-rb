# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'excon'
require 'datadog/appsec/contrib/excon/patcher'

RSpec.describe Datadog::AppSec::Contrib::Excon::Patcher do
  describe '.patch' do
    context 'when called twice via instrument' do
      before do
        described_class.instance_variable_set(:@patched, false)

        Datadog.configure do |c|
          c.appsec.enabled = true
        end
      end

      after do
        Datadog.configuration.reset!
      end

      it 'does not add SSRFDetectionMiddleware to Excon defaults twice' do
        Datadog.configuration.appsec.instrument :excon

        expect { Datadog.configuration.appsec.instrument :excon }.not_to change {
          ::Excon.defaults[:middlewares].count(Datadog::AppSec::Contrib::Excon::SSRFDetectionMiddleware)
        }
      end
    end
  end
end
