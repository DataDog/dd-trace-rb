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

      context 'when route_uri_pattern is not set and request path_parameters is empty' do
        before do
          allow(request).to receive(:env).and_return({
            'action_dispatch.routes' => route_set,
            'action_dispatch.request.path_parameters' => {}
          })
        end

        let(:router) { double('ActionDispatch::Routing::RouteSet::Router') }
        let(:route_set) { double('ActionDispatch::Routing::RouteSet', router: router) }
        let(:request) { double('Rack::Request', env: {}, script_name: '', path: '/users/1') }

        it { expect(described_class.route_pattern(request)).to eq('/users/1') }
      end

      context 'when route_uri_pattern is not set and request path_parameters is present' do
        let(:env) do
          {
            'action_dispatch.routes' => route_set,
            'action_dispatch.request.path_parameters' => {
              'controller' => 'users', 'action' => 'show', 'id' => '1'
            }
          }
        end

        context 'when request is HEAD' do
          before do
            allow(request).to receive(:env).and_return(env)
            allow(action_dispatch_request).to receive(:env).and_return(env)
          end

          let(:router) { double('ActionDispatch::Routing::RouteSet::Router') }
          let(:route_set) { double('ActionDispatch::Routing::RouteSet', router: router, request_class: action_dispatch_request_class) }
          let(:request) { double('Rack::Request', env: {}, script_name: '', path: '/users/1', head?: true) }
          let(:action_dispatch_request_class) { double('class ActionDispatch::Request', new: action_dispatch_request) }
          let(:action_dispatch_request) { double('ActionDispatch::Request', env: {}, script_name: '', path: '/users/1') }

          it 'uses action dispatch request for route recognition' do
            expect(router).to receive(:recognize).with(action_dispatch_request).and_return('/users/1')
            expect(described_class.route_pattern(request)).to eq('/users/1')
          end
        end

        context 'when request is not HEAD' do
          before { allow(request).to receive(:env).and_return(env) }

          let(:router) { double('ActionDispatch::Routing::RouteSet::Router') }
          let(:route_set) { double('ActionDispatch::Routing::RouteSet', router: router) }
          let(:request) { double('Rack::Request', env: {}, script_name: '', path: '/users/1', head?: false) }

          it 'uses action dispatch request for route recognition' do
            expect(router).to receive(:recognize).with(request).and_return('/users/1')
            expect(described_class.route_pattern(request)).to eq('/users/1')
          end
        end
      end

      context 'when Rails router cannot recognize request' do
        before do
          allow(request).to receive(:env).and_return({'action_dispatch.routes' => route_set})
          allow(request).to receive(:path).and_return('/unmatched/route')
          allow(router).to receive(:recognize).with(request).and_return([])
        end

        let(:router) { double('ActionDispatch::Routing::RouteSet::Router') }
        let(:route_set) { double('ActionDispatch::Routing::RouteSet', router: router) }

        it { expect(described_class.route_pattern(request)).to eq('/unmatched/route') }
      end
    end

    context 'when Rack routing is present' do
      context 'when route has default path' do
        it { expect(described_class.route_pattern(request)).to eq('/') }
      end

      context 'when route has nested path' do
        before { allow(request).to receive(:path).and_return('/some/other/path') }

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
