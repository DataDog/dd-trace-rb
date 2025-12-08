# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/api_security/endpoint_collection/sinatra_route_serializer'

RSpec.describe Datadog::AppSec::APISecurity::EndpointCollection::SinatraRouteSerializer do
  describe '.serialize' do
    it 'correctly serializes the route' do
      result = described_class.serialize(build_route_double(path: '/events'), method: 'GET')

      aggregate_failures 'serialized attributes' do
        expect(result.fetch(:type)).to eq('REST')
        expect(result.fetch(:resource_name)).to eq('GET /events')
        expect(result.fetch(:operation_name)).to eq('http.request')
        expect(result.fetch(:method)).to eq('GET')
        expect(result.fetch(:path)).to eq('/events')
      end
    end

    it 'adds path prefix to the route path' do
      result = described_class.serialize(build_route_double(path: '/events'), method: 'GET', path_prefix: '/sinatra')

      aggregate_failures 'path attributes' do
        expect(result.fetch(:resource_name)).to eq('GET /sinatra/events')
        expect(result.fetch(:path)).to eq('/sinatra/events')
      end
    end
  end

  def build_route_double(path:)
    instance_double('Mustermann::Sinatra', safe_string: path)
  end
end
