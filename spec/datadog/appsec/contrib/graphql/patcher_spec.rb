# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'graphql'
require 'datadog/appsec/contrib/graphql/patcher'

RSpec.describe Datadog::AppSec::Contrib::GraphQL::Patcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }
  let(:middlewares) { gateway.instance_variable_get(:@middlewares) }

  before do
    @original_patched = described_class.instance_variable_get(:@patched)
    described_class.instance_variable_set(:@patched, false)
    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)

    # Stub trace_with to prevent permanent global mutation on GraphQL::Schema
    # that would pollute other specs in this suite
    if GraphQL::Schema.respond_to?(:trace_with)
      allow(GraphQL::Schema).to receive(:trace_with)
    end

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
        Datadog.configuration.appsec.instrument :graphql

        expect { Datadog.configuration.appsec.instrument :graphql }.not_to change {
          middlewares.transform_values(&:size)
        }
      end

      # trace_with and trace_modules_for were introduced in graphql 2.0.19
      if Gem.loaded_specs['graphql'].version >= Gem::Version.new('2.0.19')
        it 'does not call trace_with on GraphQL::Schema twice' do
          Datadog.configuration.appsec.instrument :graphql
          expect(GraphQL::Schema).to have_received(:trace_with).once

          expect(GraphQL::Schema).not_to receive(:trace_with)
          Datadog.configuration.appsec.instrument :graphql
        end
      end
    end
  end
end
