# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'graphql'

RSpec.describe "Datadog::Tracing::Contrib::GraphQL::UnifiedTrace" do
  before do
    skip 'UnifiedTrace is only supported in GraphQL 2.0.19 and above' if Gem::Version.new(::GraphQL::VERSION) < Gem::Version.new('2.0.19')
    require 'datadog/tracing/contrib/graphql/unified_trace'
  end

  let(:described_class) { Datadog::Tracing::Contrib::GraphQL::UnifiedTrace }

  describe '.serialize_error_locations' do
    subject(:result) { described_class.serialize_error_locations(locations) }

    context 'when locations is nil' do
      let(:locations) { nil }

      it 'returns an empty array' do
        expect(result).to eq([])
      end
    end

    context 'when locations is an array' do
      let(:locations) do
        [
          {'line' => 3, 'column' => 10},
          {'line' => 7, 'column' => 8}
        ]
      end

      it 'maps locations to formatted strings' do
        expect(result).to eq(['3:10', '7:8'])
      end
    end

    context 'when locations is an empty array' do
      let(:locations) { [] }

      it 'returns an empty array' do
        expect(result).to eq([])
      end
    end
  end
end
