# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/api_security/route_extractor'

RSpec.describe Datadog::AppSec::APISecurity::RouteExtractor do
  describe '.route_pattern' do
    let(:request) { double('Rack::Request', env: {}, script_name: '', path: '/') }

    context 'when Sinatra routing is present' do
      context 'when route is basic' do
        before { allow(request).to receive(:env).and_return({'sinatra.route' => 'GET /users/:id'}) }

        it { expect(described_class.route_pattern(request)).to eq('/users/:id') }
      end

      context 'when app is mounted at a mount point' do
        before do
          allow(request).to receive(:env).and_return({'sinatra.route' => 'GET /users/:id'})
          allow(request).to receive(:script_name).and_return('/api/v1')
        end

        it { expect(described_class.route_pattern(request)).to eq('/api/v1/users/:id') }
      end

      context 'when route has different HTTP method' do
        before { allow(request).to receive(:env).and_return({'sinatra.route' => 'POST /users'}) }

        it { expect(described_class.route_pattern(request)).to eq('/users') }
      end
    end

    context 'when Grape routing is present' do
      let(:route_info) do
        double('Grape::Router::Route', pattern: double('Grape::Router::Pattern', origin: '/api/users/:id'))
      end

      context 'when route is basic' do
        before { allow(request).to receive(:env).and_return({'grape.routing_args' => {route_info: route_info}}) }

        it { expect(described_class.route_pattern(request)).to eq('/api/users/:id') }
      end

      context 'when app is mounted at a mount point' do
        before do
          allow(request).to receive(:env).and_return({'grape.routing_args' => {route_info: route_info}})
          allow(request).to receive(:script_name).and_return('/grape_app')
        end

        it { expect(described_class.route_pattern(request)).to eq('/grape_app/api/users/:id') }
      end

      context 'when route info is nil' do
        before { allow(request).to receive(:env).and_return({'grape.routing_args' => {route_info: nil}}) }

        it { expect(described_class.route_pattern(request)).to eq('') }
      end

      context 'when pattern is nil' do
        before do
          allow(request).to receive(:env).and_return(
            {'grape.routing_args' => {route_info: double('Grape::Router::Route', pattern: nil)}}
          )
        end

        it { expect(described_class.route_pattern(request)).to eq('') }
      end
    end

    context 'when Rails routing is present' do
      context 'when action_dispatch.route_uri_pattern is set' do
        context 'when route has format suffix' do
          before do
            allow(request).to receive(:env).and_return({'action_dispatch.route_uri_pattern' => '/users/:id(.:format)'})
          end

          it { expect(described_class.route_pattern(request)).to eq('/users/:id') }
        end

        context 'when route has no format suffix' do
          before { allow(request).to receive(:env).and_return({'action_dispatch.route_uri_pattern' => '/users/:id'}) }

          it { expect(described_class.route_pattern(request)).to eq('/users/:id') }
        end

        context 'when route has nested path' do
          before do
            allow(request).to receive(:env).and_return(
              {'action_dispatch.route_uri_pattern' => '/api/v1/users/:id/posts/:post_id(.:format)'}
            )
          end

          it { expect(described_class.route_pattern(request)).to eq('/api/v1/users/:id/posts/:post_id') }
        end
      end

      context 'when action_dispatch.route is set (Rails 8.1.1 and up)' do
        context 'when route has format suffix' do
          let(:route_double) do
            spec_double = instance_double('ActionDispatch::Journey::Nodes::Cat', to_s: '/users/:id(.:format)')
            path_double = instance_double('ActionDispatch::Journey::Path::Pattern', spec: spec_double)
            instance_double('ActionDispatch::Journey::Route', path: path_double)
          end

          before do
            allow(request).to receive(:env).and_return({'action_dispatch.route' => route_double})
          end

          it { expect(described_class.route_pattern(request)).to eq('/users/:id') }
        end

        context 'when route has no format suffix' do
          let(:route_double) do
            spec_double = instance_double('ActionDispatch::Journey::Nodes::Cat', to_s: '/users/:id')
            path_double = instance_double('ActionDispatch::Journey::Path::Pattern', spec: spec_double)
            instance_double('ActionDispatch::Journey::Route', path: path_double)
          end

          before { allow(request).to receive(:env).and_return({'action_dispatch.route' => route_double}) }

          it { expect(described_class.route_pattern(request)).to eq('/users/:id') }
        end
      end

      context 'when neither route or route_uri_pattern is set and request path_parameters are empty' do
        before do
          allow(request).to receive(:env).and_return({
            'action_dispatch.routes' => route_set,
            'action_dispatch.request.path_parameters' => {},
            'PATH_INFO' => '/users/1'
          })
        end

        let(:router) { double('ActionDispatch::Routing::RouteSet::Router') }
        let(:route_set) { double('ActionDispatch::Routing::RouteSet', router: router) }
        let(:request) { double('Rack::Request', script_name: '', path: '/users/1') }

        it { expect(described_class.route_pattern(request)).to eq('/users/{param:int}') }

        it 'persists inferred route in the request env' do
          expect { described_class.route_pattern(request) }
            .to change { request.env[Datadog::Tracing::Contrib::Rack::RouteInference::DATADOG_INFERRED_ROUTE_ENV_KEY] }
            .from(nil).to('/users/{param:int}')
        end
      end

      context 'when neither route route_uri_pattern is set and request path_parameters are present' do
        let(:env) do
          {
            'action_dispatch.routes' => route_set,
            'action_dispatch.request.path_parameters' => {
              'controller' => 'users', 'action' => 'show', 'id' => '1'
            }
          }
        end
        let(:router) { double('ActionDispatch::Routing::RouteSet::Router') }
        let(:route_set) { double('ActionDispatch::Routing::RouteSet', router: router, request_class: action_dispatch_request_class) }
        let(:action_dispatch_request_class) { double('class ActionDispatch::Request', new: action_dispatch_request) }
        let(:action_dispatch_request) { double('ActionDispatch::Request', env: {}, script_name: '', path: '/users/1') }

        before do
          allow(request).to receive(:env).and_return(env)
          allow(action_dispatch_request).to receive(:env).and_return(env)
        end

        context 'when request is HEAD' do
          let(:request) { double('Rack::Request', env: {}, script_name: '', path: '/users/1', head?: true) }

          it 'uses action dispatch request for route recognition' do
            expect(router).to receive(:recognize).with(action_dispatch_request).and_return('/users/:id(.:format)')
            expect(described_class.route_pattern(request)).to eq('/users/:id')
          end
        end

        context 'when request is not HEAD' do
          let(:request) { double('Rack::Request', env: {}, script_name: '', path: '/users/1', head?: false) }

          it 'uses action dispatch request for route recognition' do
            expect(router).to receive(:recognize).with(action_dispatch_request).and_return('/users/:id(.:format)')
            expect(described_class.route_pattern(request)).to eq('/users/:id')
          end
        end
      end

      context 'when Rails router cannot recognize request' do
        before do
          allow(request).to receive(:env).and_return({
            'action_dispatch.routes' => route_set,
            'PATH_INFO' => '/unmatched/route'
          })
          allow(router).to receive(:recognize).with(request).and_return([])
        end

        let(:router) { double('ActionDispatch::Routing::RouteSet::Router') }
        let(:route_set) { double('ActionDispatch::Routing::RouteSet', router: router) }

        it { expect(described_class.route_pattern(request)).to eq('/unmatched/route') }
      end

      context 'when an error is raised during route recognition' do
        before do
          allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)

          allow(request).to receive(:env).and_return({
            'action_dispatch.routes' => route_set,
            'action_dispatch.request.path_parameters' => {
              'controller' => 'users',
              'action' => 'show',
              'id' => '1'
            }
          })

          expect(route_set).to receive(:request_class).and_raise(StandardError)
        end

        let(:route_set) { double('ActionDispatch::Routing::RouteSet') }
        let(:telemetry) { spy(Datadog::Core::Telemetry::Component) }

        it { expect(described_class.route_pattern(request)).to be_nil }

        it 'reports the error via telemetry' do
          expect(telemetry).to receive(:report)
            .with(an_instance_of(StandardError), description: 'AppSec: Could not extract route pattern')

          described_class.route_pattern(request)
        end
      end
    end

    context 'when Rack routing is present' do
      context 'when route has default path' do
        it { expect(described_class.route_pattern(request)).to eq('/') }
      end

      context 'when route has nested path' do
        before { allow(request).to receive(:env).and_return({'PATH_INFO' => '/some/other/path'}) }

        it { expect(described_class.route_pattern(request)).to eq('/some/other/path') }
      end
    end

    context 'when multiple framework routes are present' do
      context 'when Sinatra and Grape routes are present' do
        let(:route_info) do
          double('Grape::Router::Route', pattern: double('Grape::Router::Pattern', origin: '/grape/route'))
        end

        before do
          allow(request).to receive(:env).and_return({
            'sinatra.route' => 'GET /sinatra/route',
            'grape.routing_args' => {route_info: route_info}
          })
        end

        it 'returns Grape route' do
          expect(described_class.route_pattern(request)).to eq('/grape/route')
        end
      end

      context 'when Sinatra and Rails routes are present' do
        before do
          allow(request).to receive(:env).and_return({
            'sinatra.route' => 'GET /sinatra/route',
            'action_dispatch.route_uri_pattern' => '/rails/route(.:format)'
          })
        end

        it 'returns Sinatra route' do
          expect(described_class.route_pattern(request)).to eq('/sinatra/route')
        end
      end

      context 'when Grape and Rails routes are present' do
        let(:route_info) do
          double('Grape::Router::Route', pattern: double('Grape::Router::Pattern', origin: '/grape/route'))
        end

        before do
          allow(request).to receive(:env).and_return({
            'grape.routing_args' => {route_info: route_info},
            'action_dispatch.route_uri_pattern' => '/rails/route(.:format)'
          })
        end

        it 'returns Grape route' do
          expect(described_class.route_pattern(request)).to eq('/grape/route')
        end
      end
    end
  end
end
