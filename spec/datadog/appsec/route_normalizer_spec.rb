# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/route_normalizer'

RSpec.describe Datadog::AppSec::RouteNormalizer do
  describe '.extract_normalized_route' do
    subject(:normalized_route) { described_class.extract_normalized_route(rack_env) }

    context 'with pattern input' do
      subject(:normalized_route) { described_class.extract_normalized_route({'PATH_INFO' => '/users/42'}, pattern: '/users/:id') }

      it { expect(normalized_route).to eq('/users/{id}') }
    end

    context 'with Grape route' do
      let(:rack_env) { {'grape.routing_args' => {route_info: grape_route_info(route_string)}} }

      context 'when route is static' do
        let(:route_string) { '/api/v1/health' }

        it { expect(normalized_route).to eq('/api/v1/health') }
      end

      context 'when route has named param' do
        let(:route_string) { '/api/users/:id' }

        it { expect(normalized_route).to eq('/api/users/{id}') }
      end

      context 'when route_info is nil' do
        let(:rack_env) { {'grape.routing_args' => {route_info: nil}} }

        it { expect(normalized_route).to be_nil }
      end
    end

    context 'with Sinatra route' do
      let(:rack_env) { {'sinatra.route' => sinatra_route} }

      context 'when route has named param' do
        let(:sinatra_route) { 'GET /users/:id' }

        it { expect(normalized_route).to eq('/users/{id}') }
      end

      context 'when route has nameless glob' do
        let(:sinatra_route) { 'GET /files/*' }

        it { expect(normalized_route).to eq('/files/{param1}') }
      end

      context 'when route has splat dot syntax' do
        let(:sinatra_route) { 'GET /download/*.*' }

        it { expect(normalized_route).to eq('/download/{param1+param2}') }
      end

      context 'when route has nameless glob before named param' do
        let(:sinatra_route) { 'GET /files/*.:format' }

        it { expect(normalized_route).to eq('/files/{param1+format}') }
      end
    end

    context 'with Rails Datadog route key' do
      let(:rack_env) do
        {
          'datadog.action_dispatch.route' => '/from-tracer/:id',
          'action_dispatch.route' => '/from-rails/:id',
          'action_dispatch.request.path_parameters' => {id: '42'},
          'PATH_INFO' => '/from-tracer/42',
        }
      end

      it { expect(normalized_route).to eq('/from-tracer/{id}') }
    end

    context 'with Rails native route key' do
      let(:rack_env) do
        {
          'action_dispatch.route' => '/users/:id',
          'action_dispatch.request.path_parameters' => {id: '42'},
          'PATH_INFO' => '/users/42',
        }
      end

      it { expect(normalized_route).to eq('/users/{id}') }
    end

    context 'with Rails route_uri_pattern key' do
      let(:rack_env) do
        {
          'action_dispatch.route_uri_pattern' => '/posts/:id(.:format)',
          'action_dispatch.request.path_parameters' => {id: '1', format: 'json'},
          'PATH_INFO' => '/posts/1.json',
        }
      end

      it { expect(normalized_route).to eq('/posts/{id+format}') }
    end

    context 'when nothing is available' do
      let(:rack_env) { {'PATH_INFO' => '/users/42'} }

      it { expect(normalized_route).to be_nil }
    end

    context 'when an error occurs' do
      before { allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry) }

      let(:telemetry) { instance_double('Datadog::Core::Telemetry::Component', report: nil) }
      let(:rack_env) { {'grape.routing_args' => nil} }

      it { expect(normalized_route).to be_nil }

      it 'reports the error via telemetry' do
        normalized_route

        expect(telemetry).to have_received(:report)
          .with(an_instance_of(NoMethodError), description: 'AppSec: Could not compute normalized route')
      end
    end
  end

  def grape_route_info(route_string)
    pattern = Struct.new(:origin).new(route_string)
    Struct.new(:pattern).new(pattern)
  end
end
