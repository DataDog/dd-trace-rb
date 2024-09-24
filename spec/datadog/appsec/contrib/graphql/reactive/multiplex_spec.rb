# frozen_literal_string: true

require 'datadog/tracing/contrib/graphql/test_helpers'
require 'datadog/tracing/contrib/graphql/support/application'

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/operation'
require 'datadog/appsec/contrib/graphql/gateway/multiplex'
require 'datadog/appsec/contrib/graphql/reactive/multiplex'
require 'datadog/appsec/reactive/shared_examples'

RSpec.describe Datadog::AppSec::Contrib::GraphQL::Reactive::Multiplex do
  include_context 'with GraphQL multiplex'

  let(:expected_arguments) do
    {
      'user' => [{ 'id' => 1 }, { 'id' => 10 }],
      'userByName' => [{ 'name' => 'Caniche' }]
    }
  end

  describe '.publish' do
    it 'propagates multiplex attributes to the operation' do
      expect(operation).to receive(:publish).with('graphql.server.all_resolvers', expected_arguments)
      gateway_multiplex = Datadog::AppSec::Contrib::GraphQL::Gateway::Multiplex.new(multiplex)
      described_class.publish(operation, gateway_multiplex)
    end
  end

  describe '.subscribe' do
    let(:waf_context) { double(:waf_context) }

    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(operation).to receive(:subscribe).with(
          'graphql.server.all_resolvers'
        ).and_call_original
        expect(waf_context).to_not receive(:run)
        described_class.subscribe(operation, waf_context)
      end
    end

    context 'all addresses have been published' do
      it 'does call the waf context with the right arguments' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :ok, timeout: false)
        expect(waf_context).to receive(:run).with(
          { 'graphql.server.all_resolvers' => expected_arguments },
          Datadog.configuration.appsec.waf_timeout
        ).and_return(waf_result)
        described_class.subscribe(operation, waf_context)
        gateway_multiplex = Datadog::AppSec::Contrib::GraphQL::Gateway::Multiplex.new(multiplex)
        result = described_class.publish(operation, gateway_multiplex)
        expect(result).to be_nil
      end
    end

    it_behaves_like 'waf result' do
      let(:gateway) { Datadog::AppSec::Contrib::GraphQL::Gateway::Multiplex.new(multiplex) }
    end
  end
end
