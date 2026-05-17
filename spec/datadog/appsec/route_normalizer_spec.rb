# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/route_normalizer'

RSpec.describe Datadog::AppSec::RouteNormalizer do
  describe '.normalize' do
    context 'when route is static' do
      it { expect(described_class.normalize('/users', {}, '/')).to eq('/users') }
    end

    context 'when route has named param' do
      it { expect(described_class.normalize('/users/:id', {}, '/')).to eq('/users/{id}') }
    end

    context 'when route has glob param' do
      it { expect(described_class.normalize('/files/*path', {}, '/')).to eq('/files/{path}') }
    end

    context 'when route has multiple params in one segment' do
      it { expect(described_class.normalize('/photos/:id.:format', {}, '/')).to eq('/photos/{id+format}') }
    end

    context 'when route has three params in one segment' do
      it { expect(described_class.normalize('/:a.:b.:c', {}, '/')).to eq('/{a+b+c}') }
    end

    context 'when route has mixed static and dynamic segment' do
      it { expect(described_class.normalize('/users/user-:id', {}, '/')).to eq('/users/{id}') }
    end

    context 'when route has optional present' do
      it 'keeps the optional group content' do
        expect(described_class.normalize(
          '/books(/:category)',
          {category: 'fiction'},
          '/books/fiction',
        )).to eq('/books/{category}')
      end
    end

    context 'when route has optional absent' do
      it 'removes the optional group' do
        expect(described_class.normalize(
          '/books(/:category)',
          {},
          '/books',
        )).to eq('/books')
      end
    end

    context 'when route has optional with nil param' do
      it 'removes the optional group' do
        expect(described_class.normalize(
          '/books(/:category)',
          {category: nil},
          '/books',
        )).to eq('/books')
      end
    end

    context 'when route has optional with Symbol param' do
      it 'removes the optional group' do
        expect(described_class.normalize(
          '/items(/:type)',
          {type: :default},
          '/items',
        )).to eq('/items')
      end
    end

    context 'when route has format present in URL' do
      it 'keeps the format group' do
        expect(described_class.normalize(
          '/posts/:id(.:format)',
          {id: '1', format: 'json'},
          '/posts/1.json',
        )).to eq('/posts/{id+format}')
      end
    end

    context 'when route has format nil' do
      it 'removes the format group' do
        expect(described_class.normalize(
          '/posts/:id(.:format)',
          {id: '1', format: nil},
          '/posts/1',
        )).to eq('/posts/{id}')
      end
    end

    context 'when route has format as Symbol default' do
      it 'removes the format group' do
        expect(described_class.normalize(
          '/posts/:id(.:format)',
          {id: '1', format: :json},
          '/posts/1',
        )).to eq('/posts/{id}')
      end
    end

    context 'when route has format as String default not in URL' do
      it 'removes the format group' do
        expect(described_class.normalize(
          '/posts/:id(.:format)',
          {id: '1', format: 'json'},
          '/posts/1',
        )).to eq('/posts/{id}')
      end
    end

    context 'when route has nested optionals with all present' do
      it 'keeps all groups' do
        expect(described_class.normalize(
          '/posts(/:year(/:month(/:day)))',
          {year: '2024', month: '01', day: '15'},
          '/posts/2024/01/15',
        )).to eq('/posts/{year}/{month}/{day}')
      end
    end

    context 'when route has nested optionals with only year present' do
      it 'keeps only year' do
        expect(described_class.normalize(
          '/posts(/:year(/:month(/:day)))',
          {year: '2024'},
          '/posts/2024',
        )).to eq('/posts/{year}')
      end
    end

    context 'when route has nested optionals with none present' do
      it 'removes all groups' do
        expect(described_class.normalize(
          '/posts(/:year(/:month(/:day)))',
          {},
          '/posts',
        )).to eq('/posts')
      end
    end

    context 'when route has catch-all' do
      it { expect(described_class.normalize('/*path', {}, '/')).to eq('/{path}') }
    end

    context 'when route has static chars needing URL encoding' do
      it { expect(described_class.normalize('/hello world', {}, '/')).to eq('/hello%20world') }
    end

    context 'when route has no params at all' do
      it { expect(described_class.normalize('/api/v1/health', {}, '/')).to eq('/api/v1/health') }
    end

    context 'when route is root' do
      it { expect(described_class.normalize('/', {}, '/')).to eq('/') }
    end
  end

  describe '.format_in_url?' do
    it { expect(described_class.format_in_url?(nil, '/posts/1')).to be(false) }
    it { expect(described_class.format_in_url?(:json, '/posts/1.json')).to be(false) }
    it { expect(described_class.format_in_url?('json', '/posts/1.json')).to be(true) }
    it { expect(described_class.format_in_url?('json', '/posts/1')).to be(false) }
    it { expect(described_class.format_in_url?('xml', '/posts/1.json')).to be(false) }
  end

  describe '.route_spec' do
    subject(:result) { described_class.route_spec(env) }

    context 'when Grape route key is present' do
      let(:route_info) { double('Grape::Router::Route', pattern: double('Grape::Router::Pattern', origin: '/api/users/:id')) }
      let(:env) { {'grape.routing_args' => {route_info: route_info}} }

      it { expect(result).to eq('/api/users/:id') }
    end

    context 'when Grape route_info is nil' do
      let(:env) { {'grape.routing_args' => {route_info: nil}} }

      it { expect(result).to be_nil }
    end

    context 'when Sinatra route key is present' do
      let(:env) { {'sinatra.route' => 'GET /users/:id'} }

      it { expect(result).to eq('/users/:id') }
    end

    context 'when datadog route key is present' do
      let(:route) { instance_double('ActionDispatch::Journey::Route', path: path) }
      let(:path) { instance_double('ActionDispatch::Journey::Path::Pattern', spec: spec) }
      let(:spec) { instance_double('ActionDispatch::Journey::Format', to_s: '/users/:id(.:format)') }
      let(:env) { {'datadog.action_dispatch.route' => route} }

      it { expect(result).to eq('/users/:id(.:format)') }
    end

    context 'when Rails 8.1.1+ route key is present' do
      let(:route) { instance_double('ActionDispatch::Journey::Route', path: path) }
      let(:path) { instance_double('ActionDispatch::Journey::Path::Pattern', spec: spec) }
      let(:spec) { instance_double('ActionDispatch::Journey::Format', to_s: '/users/:id(.:format)') }
      let(:env) { {'action_dispatch.route' => route} }

      it { expect(result).to eq('/users/:id(.:format)') }
    end

    context 'when Rails route_uri_pattern is present' do
      let(:env) { {'action_dispatch.route_uri_pattern' => '/users/:id(.:format)'} }

      it { expect(result).to eq('/users/:id(.:format)') }
    end

    context 'when TAG_ROUTE is available from active trace' do
      let(:trace) { instance_double('Datadog::Tracing::TraceOperation') }
      let(:env) { {} }

      before do
        allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
        allow(trace).to receive(:get_tag)
          .with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_ROUTE)
          .and_return('/users/:id')
      end

      it { expect(result).to eq('/users/:id') }
    end

    context 'when nothing is available' do
      let(:env) { {} }

      before { allow(Datadog::Tracing).to receive(:active_trace).and_return(nil) }

      it { expect(result).to be_nil }
    end

    context 'when datadog key takes priority over Rails native key' do
      let(:datadog_route) do
        path = instance_double('ActionDispatch::Journey::Path::Pattern',
          spec: instance_double('ActionDispatch::Journey::Format', to_s: '/from-tracer/:id(.:format)'))
        instance_double('ActionDispatch::Journey::Route', path: path)
      end
      let(:rails_route) do
        path = instance_double('ActionDispatch::Journey::Path::Pattern',
          spec: instance_double('ActionDispatch::Journey::Format', to_s: '/from-rails/:id(.:format)'))
        instance_double('ActionDispatch::Journey::Route', path: path)
      end
      let(:env) do
        {
          'datadog.action_dispatch.route' => datadog_route,
          'action_dispatch.route' => rails_route,
        }
      end

      it { expect(result).to eq('/from-tracer/:id(.:format)') }
    end
  end

  describe '.normalized_route' do
    subject(:result) { described_class.normalized_route(env) }

    context 'when route spec is available' do
      let(:route) do
        path = instance_double('ActionDispatch::Journey::Path::Pattern',
          spec: instance_double('ActionDispatch::Journey::Format', to_s: '/users/:id(.:format)'))
        instance_double('ActionDispatch::Journey::Route', path: path)
      end
      let(:env) do
        {
          'datadog.action_dispatch.route' => route,
          'action_dispatch.request.path_parameters' => {id: '42', format: nil},
          'PATH_INFO' => '/users/42',
        }
      end

      it { expect(result).to eq('/users/{id}') }
    end

    context 'when route spec is not available' do
      let(:env) { {'PATH_INFO' => '/users/42'} }

      before { allow(Datadog::Tracing).to receive(:active_trace).and_return(nil) }

      it { expect(result).to be_nil }
    end

    context 'when an error occurs' do
      let(:telemetry) { instance_double('Datadog::Core::Telemetry::Component', report: nil) }
      let(:env) { {} }

      before do
        allow(described_class).to receive(:route_spec).and_raise(StandardError, 'boom')
        allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
      end

      it { expect(result).to be_nil }

      it 'reports the error via telemetry' do
        result
        expect(telemetry).to have_received(:report)
          .with(an_instance_of(StandardError), description: 'Could not compute normalized route')
      end
    end
  end
end
