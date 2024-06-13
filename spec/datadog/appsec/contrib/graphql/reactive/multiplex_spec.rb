# frozen_literal_string: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/operation'
require 'datadog/appsec/contrib/graphql/gateway/multiplex'
require 'datadog/appsec/contrib/graphql/reactive/multiplex'

require 'graphql'

require_relative '../../../../tracing/contrib/graphql/test_helpers'

class TestUserType < ::GraphQL::Schema::Object
  field :id, ::GraphQL::Types::ID, null: false
  field :name, ::GraphQL::Types::String, null: true
  field :created_at, ::GraphQL::Types::String, null: false
  field :updated_at, ::GraphQL::Types::String, null: false
end

class TestGraphQLQuery < ::GraphQL::Schema::Object
  field :user, TestUserType, null: false, description: 'Find an user by ID' do
    argument :id, ::GraphQL::Types::ID, required: true
  end

  def user(id:)
    return OpenStruct.new(id: id, name: 'Zidane') if id == 10

    OpenStruct.new(id: id, name: 'Bits')
  end
end

class TestGraphQLSchema < ::GraphQL::Schema
  query(TestGraphQLQuery)
end

RSpec.describe Datadog::AppSec::Contrib::GraphQL::Reactive::Multiplex do
  let(:operation) { Datadog::AppSec::Reactive::Operation.new('test') }
  let(:schema) { TestGraphQLSchema }
  let(:first_query) { ::GraphQL::Query.new(schema, 'query test{ user(id: 1) { name } }') }
  let(:second_query) { ::GraphQL::Query.new(schema, 'query test{ user(id: 10) { name } }') }
  let(:third_query) { ::GraphQL::Query.new(schema, 'query { user(id: 5) { name } }') }
  let(:queries) { [first_query, second_query, third_query] }
  let(:context) { { :dataloader => GraphQL::Dataloader.new(nonblocking: nil) } }
  let(:multiplex) do
    Datadog::AppSec::Contrib::GraphQL::Gateway::Multiplex.new(
      ::GraphQL::Execution::Multiplex.new(schema: schema, queries: queries, context: context, max_complexity: nil)
    )
  end

  let(:expected_arguments) { { 'test' => [{ 'id' => 1 }, { 'id' => 10 }], 'query3' => [{ 'id' => 5 }] } }

  describe '.publish' do
    it 'propagates multiplex attributes to the operation' do
      expect(operation).to receive(:publish).with('graphql.server.all_resolvers', expected_arguments)

      described_class.publish(operation, multiplex)
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
        result = described_class.publish(operation, multiplex)
        expect(result).to be_nil
      end
    end

    context 'waf result is a match' do
      it 'yields result and no blocking action' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :match, timeout: false, actions: [])
        expect(waf_context).to receive(:run).and_return(waf_result)
        described_class.subscribe(operation, waf_context) do |result|
          expect(result).to eq(waf_result)
        end
        result = described_class.publish(operation, multiplex)
        expect(result).to be_nil
      end

      it 'yields result and blocking action. The publish method catches the resul as well' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :match, timeout: false, actions: ['block'])
        expect(waf_context).to receive(:run).and_return(waf_result)
        described_class.subscribe(operation, waf_context) do |result|
          expect(result).to eq(waf_result)
        end
        block = described_class.publish(operation, multiplex)
        expect(block).to eq(true)
      end
    end

    context 'waf result is ok' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :ok, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, multiplex)
        expect(result).to be_nil
      end
    end

    context 'waf result is invalid_call' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :invalid_call, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, multiplex)
        expect(result).to be_nil
      end
    end

    context 'waf result is invalid_rule' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :invalid_rule, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, multiplex)
        expect(result).to be_nil
      end
    end

    context 'waf result is invalid_flow' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :invalid_flow, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, multiplex)
        expect(result).to be_nil
      end
    end

    context 'waf result is no_rule' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :no_rule, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, multiplex)
        expect(result).to be_nil
      end
    end

    context 'waf result is unknown' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :foo, timeout: false)
        expect(waf_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, waf_context, &b) }.not_to yield_control
        result = described_class.publish(operation, multiplex)
        expect(result).to be_nil
      end
    end
  end
end
