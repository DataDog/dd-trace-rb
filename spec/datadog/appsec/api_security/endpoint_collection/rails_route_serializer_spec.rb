# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/api_security/endpoint_collection/rails_route_serializer'

RSpec.describe Datadog::AppSec::APISecurity::EndpointCollection::RailsRouteSerializer do
  describe '.serialize' do
    it 'correctly serializes the route' do
      result = described_class.serialize(build_route_double(method: 'GET', path: '/events'))

      aggregate_failures 'serialized attributes' do
        expect(result.fetch(:type)).to eq('REST')
        expect(result.fetch(:resource_name)).to eq('GET /events')
        expect(result.fetch(:operation_name)).to eq('http.request')
        expect(result.fetch(:method)).to eq('GET')
        expect(result.fetch(:path)).to eq('/events')
      end
    end

    it 'removes rails format suffix from the path' do
      result = described_class.serialize(build_route_double(method: 'GET', path: '/events(.:format)'))

      aggregate_failures 'path attributes' do
        expect(result.fetch(:resource_name)).to eq('GET /events')
        expect(result.fetch(:path)).to eq('/events')
      end
    end

    it 'sets method to * for wildcard routes' do
      result = described_class.serialize(build_route_double(method: '*', path: '/'))

      aggregate_failures 'path attributes' do
        expect(result.fetch(:resource_name)).to eq('* /')
        expect(result.fetch(:method)).to eq('*')
      end
    end

    it 'uses specified method in method_override argument' do
      result = described_class.serialize(
        build_route_double(method: 'GET|POST', path: '/search'),
        method_override: 'GET'
      )

      aggregate_failures 'path attributes' do
        expect(result.fetch(:resource_name)).to eq('GET /search')
        expect(result.fetch(:method)).to eq('GET')
      end
    end
  end

  def build_route_double(path:, method:)
    instance_double(
      'ActionDispatch::Journey::Route',
      verb: method,
      path: instance_double('ActionDispatch::Journey::Path::Pattern', spec: path)
    )
  end
end
