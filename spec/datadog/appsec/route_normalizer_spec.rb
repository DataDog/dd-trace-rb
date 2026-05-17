# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/route_normalizer'

MockAstNode = Struct.new(:type, :left, :right, :name) do
  include Enumerable

  def each(&block)
    return enum_for(:each) unless block
    yield self
    case type
    when :CAT
      left.each(&block)
      right.each(&block)
    when :GROUP, :STAR
      left.each(&block)
    end
  end

  def to_s
    case type
    when :CAT then "#{left}#{right}"
    when :SLASH then '/'
    when :LITERAL then left
    when :DOT then '.'
    when :SYMBOL then ":#{name}"
    when :STAR then "*#{name}"
    when :GROUP then "(#{left})"
    else ''
    end
  end
end

RSpec.describe Datadog::AppSec::RouteNormalizer do
  describe '.normalized_route' do
    subject(:result) { described_class.normalized_route(env) }

    context 'with Grape route' do
      let(:route_info) { double('Grape::Router::Route', pattern: double('Grape::Router::Pattern', origin: route_string)) }
      let(:env) { {'grape.routing_args' => {route_info: route_info}, 'PATH_INFO' => path} }

      context 'when route is static' do
        let(:route_string) { '/api/v1/health' }
        let(:path) { '/api/v1/health' }

        it { expect(result).to eq('/api/v1/health') }
      end

      context 'when route has named param' do
        let(:route_string) { '/api/users/:id' }
        let(:path) { '/api/users/42' }

        it { expect(result).to eq('/api/users/{id}') }
      end

      context 'when route_info is nil' do
        let(:env) { {'grape.routing_args' => {route_info: nil}} }

        it { expect(result).to be_nil }
      end
    end

    context 'with Sinatra route' do
      let(:env) { {'sinatra.route' => sinatra_route, 'PATH_INFO' => path} }

      context 'when route has named param' do
        let(:sinatra_route) { 'GET /users/:id' }
        let(:path) { '/users/42' }

        it { expect(result).to eq('/users/{id}') }
      end

      context 'when route has nameless glob' do
        let(:sinatra_route) { 'GET /files/*' }
        let(:path) { '/files/a/b/c' }

        it { expect(result).to eq('/files/{param1}') }
      end

      context 'when route has splat dot syntax' do
        let(:sinatra_route) { 'GET /download/*.*' }
        let(:path) { '/download/file.tar.gz' }

        it { expect(result).to eq('/download/{param1+param2}') }
      end

      context 'when route has nameless glob before named param' do
        let(:sinatra_route) { 'GET /files/*.:format' }
        let(:path) { '/files/readme.txt' }

        it { expect(result).to eq('/files/{param1+format}') }
      end

      context 'when route is static' do
        let(:sinatra_route) { 'GET /status' }
        let(:path) { '/status' }

        it { expect(result).to eq('/status') }
      end
    end

    context 'with Rails Journey route object' do
      let(:env) do
        {
          'datadog.action_dispatch.route' => route,
          'action_dispatch.request.path_parameters' => path_params,
          'PATH_INFO' => path,
        }
      end

      context 'when route is static' do
        let(:route) { build_rails_route(lit('/'), lit('users')) }
        let(:path_params) { {} }
        let(:path) { '/users' }

        it { expect(result).to eq('/users') }
      end

      context 'when route has named param' do
        let(:route) { build_rails_route(lit('/'), lit('users'), lit('/'), sym('id')) }
        let(:path_params) { {id: '42'} }
        let(:path) { '/users/42' }

        it { expect(result).to eq('/users/{id}') }
      end

      context 'when route has glob param' do
        let(:route) { build_rails_route(lit('/'), lit('files'), lit('/'), star('path')) }
        let(:path_params) { {path: 'a/b/c'} }
        let(:path) { '/files/a/b/c' }

        it { expect(result).to eq('/files/{path}') }
      end

      context 'when route has multiple params in one segment' do
        let(:route) { build_rails_route(lit('/'), lit('photos'), lit('/'), sym('id'), dot, sym('format')) }
        let(:path_params) { {id: '1', format: 'json'} }
        let(:path) { '/photos/1.json' }

        it { expect(result).to eq('/photos/{id+format}') }
      end

      context 'when route has three params in one segment' do
        let(:route) { build_rails_route(lit('/'), sym('a'), dot, sym('b'), dot, sym('c')) }
        let(:path_params) { {a: '1', b: '2', c: '3'} }
        let(:path) { '/1.2.3' }

        it { expect(result).to eq('/{a+b+c}') }
      end

      context 'when route has mixed static and dynamic segment' do
        let(:route) { build_rails_route(lit('/'), lit('users'), lit('/'), lit('user-'), sym('id')) }
        let(:path_params) { {id: '42'} }
        let(:path) { '/users/user-42' }

        it { expect(result).to eq('/users/{id}') }
      end

      context 'when route has optional format present in URL' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('posts'), lit('/'), sym('id'),
            group(dot, sym('format')),
          )
        end
        let(:path_params) { {id: '1', format: 'json'} }
        let(:path) { '/posts/1.json' }

        it { expect(result).to eq('/posts/{id+format}') }
      end

      context 'when route has optional format nil' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('posts'), lit('/'), sym('id'),
            group(dot, sym('format')),
          )
        end
        let(:path_params) { {id: '1', format: nil} }
        let(:path) { '/posts/1' }

        it { expect(result).to eq('/posts/{id}') }
      end

      context 'when route has optional format as Symbol default' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('posts'), lit('/'), sym('id'),
            group(dot, sym('format')),
          )
        end
        let(:path_params) { {id: '1', format: :json} }
        let(:path) { '/posts/1' }

        it { expect(result).to eq('/posts/{id}') }
      end

      context 'when route has optional format as String default not in URL' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('posts'), lit('/'), sym('id'),
            group(dot, sym('format')),
          )
        end
        let(:path_params) { {id: '1', format: 'json'} }
        let(:path) { '/posts/1' }

        it { expect(result).to eq('/posts/{id}') }
      end

      context 'when route has optional param present' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('books'),
            group(lit('/'), sym('category')),
          )
        end
        let(:path_params) { {category: 'fiction'} }
        let(:path) { '/books/fiction' }

        it { expect(result).to eq('/books/{category}') }
      end

      context 'when route has optional param absent' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('books'),
            group(lit('/'), sym('category')),
          )
        end
        let(:path_params) { {} }
        let(:path) { '/books' }

        it { expect(result).to eq('/books') }
      end

      context 'when route has optional param nil' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('books'),
            group(lit('/'), sym('category')),
          )
        end
        let(:path_params) { {category: nil} }
        let(:path) { '/books' }

        it { expect(result).to eq('/books') }
      end

      context 'when route has optional param with Symbol value' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('items'),
            group(lit('/'), sym('type')),
          )
        end
        let(:path_params) { {type: :default} }
        let(:path) { '/items' }

        it { expect(result).to eq('/items') }
      end

      context 'when route has nested optionals with all present' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('posts'),
            group(lit('/'), sym('year'),
              group(lit('/'), sym('month'),
                group(lit('/'), sym('day')))),
          )
        end
        let(:path_params) { {year: '2024', month: '01', day: '15'} }
        let(:path) { '/posts/2024/01/15' }

        it { expect(result).to eq('/posts/{year}/{month}/{day}') }
      end

      context 'when route has nested optionals with only year present' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('posts'),
            group(lit('/'), sym('year'),
              group(lit('/'), sym('month'),
                group(lit('/'), sym('day')))),
          )
        end
        let(:path_params) { {year: '2024'} }
        let(:path) { '/posts/2024' }

        it { expect(result).to eq('/posts/{year}') }
      end

      context 'when route has nested optionals with none present' do
        let(:route) do
          build_rails_route(
            lit('/'), lit('posts'),
            group(lit('/'), sym('year'),
              group(lit('/'), sym('month'),
                group(lit('/'), sym('day')))),
          )
        end
        let(:path_params) { {} }
        let(:path) { '/posts' }

        it { expect(result).to eq('/posts') }
      end

      context 'when route has catch-all' do
        let(:route) { build_rails_route(lit('/'), star('path')) }
        let(:path_params) { {path: 'a/b/c'} }
        let(:path) { '/a/b/c' }

        it { expect(result).to eq('/{path}') }
      end

      context 'when route has static chars needing URL encoding' do
        let(:route) { build_rails_route(lit('/'), lit('hello world')) }
        let(:path_params) { {} }
        let(:path) { '/hello%20world' }

        it { expect(result).to eq('/hello%20world') }
      end

      context 'when route has multi-byte static chars' do
        let(:route) { build_rails_route(lit('/'), lit('café')) }
        let(:path_params) { {} }
        let(:path) { '/caf%C3%A9' }

        it { expect(result).to eq('/caf%C3%A9') }
      end

      context 'when route is root' do
        let(:route) { build_rails_route(lit('/')) }
        let(:path_params) { {} }
        let(:path) { '/' }

        it { expect(result).to eq('/') }
      end

      context 'when route has trailing slash' do
        let(:route) { build_rails_route(lit('/'), lit('users'), lit('/')) }
        let(:path_params) { {} }
        let(:path) { '/users/' }

        it { expect(result).to eq('/users/') }
      end
    end

    context 'with Rails native route key' do
      let(:route) { build_rails_route(lit('/'), lit('users'), lit('/'), sym('id')) }
      let(:env) do
        {
          'action_dispatch.route' => route,
          'action_dispatch.request.path_parameters' => {id: '42'},
          'PATH_INFO' => '/users/42',
        }
      end

      it { expect(result).to eq('/users/{id}') }
    end

    context 'with Rails route_uri_pattern string' do
      let(:env) do
        {
          'action_dispatch.route_uri_pattern' => '/posts/:id(.:format)',
          'action_dispatch.request.path_parameters' => path_params,
          'PATH_INFO' => path,
        }
      end

      context 'when format is present in URL' do
        let(:path_params) { {id: '1', format: 'json'} }
        let(:path) { '/posts/1.json' }

        it { expect(result).to eq('/posts/{id+format}') }
      end

      context 'when format is absent' do
        let(:path_params) { {id: '1', format: nil} }
        let(:path) { '/posts/1' }

        it { expect(result).to eq('/posts/{id}') }
      end

      context 'when route has nested optionals' do
        let(:env) do
          {
            'action_dispatch.route_uri_pattern' => '/posts(/:year(/:month))',
            'action_dispatch.request.path_parameters' => {year: '2024'},
            'PATH_INFO' => '/posts/2024',
          }
        end

        it { expect(result).to eq('/posts/{year}') }
      end
    end

    context 'with trace tag fallback' do
      before do
        allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
        allow(trace).to receive(:get_tag)
          .with(Datadog::Tracing::Metadata::Ext::HTTP::TAG_ROUTE)
          .and_return('/users/:id')
      end

      let(:trace) { instance_double('Datadog::Tracing::TraceOperation') }
      let(:env) { {'PATH_INFO' => '/users/42'} }

      it { expect(result).to eq('/users/{id}') }
    end

    context 'when datadog key takes priority over Rails native key' do
      let(:datadog_route) { build_rails_route(lit('/'), lit('from-tracer'), lit('/'), sym('id')) }
      let(:rails_route) { build_rails_route(lit('/'), lit('from-rails'), lit('/'), sym('id')) }
      let(:env) do
        {
          'datadog.action_dispatch.route' => datadog_route,
          'action_dispatch.route' => rails_route,
          'action_dispatch.request.path_parameters' => {id: '42'},
          'PATH_INFO' => '/from-tracer/42',
        }
      end

      it { expect(result).to eq('/from-tracer/{id}') }
    end

    context 'when nothing is available' do
      before { allow(Datadog::Tracing).to receive(:active_trace).and_return(nil) }

      let(:env) { {'PATH_INFO' => '/users/42'} }

      it { expect(result).to be_nil }
    end

    context 'when an error occurs' do
      before { allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry) }

      let(:telemetry) { instance_double('Datadog::Core::Telemetry::Component', report: nil) }
      let(:env) { {'grape.routing_args' => nil} }

      it { expect(result).to be_nil }

      it 'reports the error via telemetry' do
        result
        expect(telemetry).to have_received(:report)
          .with(an_instance_of(NoMethodError), description: 'Could not compute normalized route')
      end
    end
  end

  def lit(text)
    return MockAstNode.new(:SLASH, '/') if text == '/'

    MockAstNode.new(:LITERAL, text)
  end

  def dot
    MockAstNode.new(:DOT, '.')
  end

  def sym(name)
    MockAstNode.new(:SYMBOL, ":#{name}", nil, name)
  end

  def star(name)
    MockAstNode.new(:STAR, sym(name), nil, name)
  end

  def group(*nodes)
    MockAstNode.new(:GROUP, cat(*nodes))
  end

  def cat(*nodes)
    nodes.reduce { |l, r| MockAstNode.new(:CAT, l, r) }
  end

  def build_rails_route(*nodes)
    spec = (nodes.size == 1) ? nodes[0] : cat(*nodes)
    names = []
    spec.each { |n| names << n.name if n.is_a?(MockAstNode) && n.type == :SYMBOL }
    path = double('Path::Pattern', spec: spec, names: names)
    double('Journey::Route', path: path)
  end
end
