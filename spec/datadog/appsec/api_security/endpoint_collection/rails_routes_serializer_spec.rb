# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/api_security/endpoint_collection/rails_routes_serializer'

RSpec.describe Datadog::AppSec::APISecurity::EndpointCollection::RailsRoutesSerializer do
  describe '#to_enum' do
    it 'returns an Enumerator' do
      expect(described_class.new([]).to_enum).to be_a(Enumerator)
    end

    it 'correctly serializes routes' do
      routes = described_class.new([
        build_route_double(method: 'GET', path: '/events')
      ]).to_enum

      expect(routes.count).to eq(1)

      aggregate_failures 'serialized attributes' do
        expect(routes.first.fetch(:type)).to eq('REST')
        expect(routes.first.fetch(:resource_name)).to eq('GET /events')
        expect(routes.first.fetch(:operation_name)).to eq('http.request')
        expect(routes.first.fetch(:method)).to eq('GET')
        expect(routes.first.fetch(:path)).to eq('/events')
      end
    end

    it 'removes rails format suffix from the path' do
      routes = described_class.new([
        build_route_double(method: 'GET', path: '/events(.:format)')
      ]).to_enum

      aggregate_failures 'path attributes' do
        expect(routes.first.fetch(:resource_name)).to eq('GET /events')
        expect(routes.first.fetch(:path)).to eq('/events')
      end
    end

    it 'sets method to * for wildcard routes' do
      routes = described_class.new([
        build_route_double(method: '*', path: '/')
      ]).to_enum

      aggregate_failures 'path attributes' do
        expect(routes.first.fetch(:resource_name)).to eq('* /')
        expect(routes.first.fetch(:method)).to eq('*')
      end
    end

    it 'skips non-dispatcher routes for now' do
      routes = described_class.new([
        build_route_double(method: nil, path: 'admin', is_dispatcher: false)
      ]).to_enum

      expect(routes.to_a).to be_empty
    end
  end

  def build_route_double(method:, path:, is_dispatcher: true)
    instance_double(
      'ActionDispatch::Journey::Route',
      dispatcher?: is_dispatcher,
      verb: method,
      path: instance_double(
        'ActionDispatch::Journey::Path::Pattern',
        spec: path
      ),
      app: instance_double(
        'ActionDispatch::Routing::RouteSet::Dispatcher',
        rack_app: instance_double(
          'ActionDispatch::Routing::RouteSet::Dispatcher'
        )
      )
    )
  end
end
