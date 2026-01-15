# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/api_security/endpoint_collection/rails_collector'

RSpec.describe Datadog::AppSec::APISecurity::EndpointCollection::RailsCollector do
  describe '#to_enum' do
    it 'returns an Enumerator' do
      expect(described_class.new([]).to_enum).to be_a(Enumerator)
    end

    it 'serializes Rails dispatcher routes' do
      route = instance_double(
        'ActionDispatch::Journey::Route', dispatcher?: true, verb: 'GET',
        path: instance_double('ActionDispatch::Journey::Path::Pattern', spec: '/events')
      )

      expect(Datadog::AppSec::APISecurity::EndpointCollection::RailsRouteSerializer)
        .to receive(:serialize).and_call_original

      described_class.new([route]).to_enum.first
    end

    it 'serializes Rails dispatcher routes that support multiple methods' do
      route = instance_double(
        'ActionDispatch::Journey::Route', dispatcher?: true, verb: 'GET|POST',
        path: instance_double('ActionDispatch::Journey::Path::Pattern', spec: '/events')
      )

      expect(Datadog::AppSec::APISecurity::EndpointCollection::RailsRouteSerializer)
        .to receive(:serialize).twice.and_call_original

      described_class.new([route]).to_enum.first(2)
    end

    # Grape and Sinatra routes are tested in endpoint collection integration test,
    # to avoid adding grape and sinatra dependencies for unit tests
  end
end
