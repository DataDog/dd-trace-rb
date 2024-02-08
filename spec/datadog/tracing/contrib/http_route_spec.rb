require 'datadog/tracing/contrib/support/spec_helper'

require 'grape'
require 'rack/test'
require 'sinatra'
require 'rails'
require 'action_controller'

require 'ddtrace'

RSpec.describe 'Multi-app testing for http.route' do
  include Rack::Test::Methods

  let(:options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :sinatra, options
      c.tracing.instrument :rack, options
      c.tracing.instrument :grape, options
      c.tracing.instrument :rails, options
    end
  end

  after do
    Datadog.registry[:sinatra].reset_configuration!
    Datadog.registry[:rack].reset_configuration!
    Datadog.registry[:grape].reset_configuration!
    Datadog.registry[:rails].reset_configuration!
  end

  shared_context 'multi-app' do
    let(:app) do
      apps_to_build = apps

      Rack::Builder.new do
        apps_to_build.each do |route, app|
          map route do
            run app
          end
        end
      end.to_app
    end

    let(:apps) do
      {
        '/' => rack_app,
        '/rack' => rack_app,
        '/sinatra' => sinatra_app,
        '/grape' => grape_app,
        '/rails' => rails_app,
        '/rack/rack' => rack_app,
        '/rack/sinatra' => sinatra_app,
        '/rack/grape' => grape_app,
        '/rack/rails' => rails_app
      }
    end

    let(:rack_app) do
      Rack::Builder.new do
        map '/hello/world' do
          run ->(_env) { [200, { 'content-type' => 'text/plain' }, 'hello world'] }
        end
      end
    end

    let(:sinatra_app) do
      Class.new(Sinatra::Application) do
        get '/hello/world' do
          'hello world'
        end

        get '/hello/:id' do
          "hello #{params[:id]}"
        end
      end
    end

    let(:grape_app) do
      Class.new(Grape::API) do
        get '/hello/world' do
          'hello world'
        end
        get '/hello/:id' do
          "hello #{params[:id]}"
        end
      end
    end

    let(:rails_app) do
      Class.new(Rails::Engine) do
        routes.draw do
          get '/hello/world' => 'hello#world'
          get '/hello/:id' => 'hello#show'
        end
      end
    end

    before do
      stub_const(
        'HelloController',
        Class.new(ActionController::Base) do
          def world
            render plain: 'Hello, world!'
          end

          def show
            render plain: "Hello, #{params[:id]}!"
          end
        end
      )
    end
  end

  context 'base routes' do
    include_context 'multi-app'

    describe 'request to base app' do
      subject(:response) { get '/hello/world' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/hello/world')

          break
        end
      end
    end

    describe 'request to rack app' do
      subject(:response) { get '/rack/hello/world' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/rack/hello/world')

          break
        end
      end
    end

    describe 'request to sinatra app' do
      subject(:response) { get '/sinatra/hello/world' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/sinatra/hello/world')

          break
        end
      end
    end

    describe 'request to sinatra app w/param' do
      subject(:response) { get '/sinatra/hello/7' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/sinatra/hello/:id')

          break
        end
      end
    end

    describe 'request to grape app' do
      subject(:response) { get '/grape/hello/world' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/grape/hello/world')

          break
        end
      end
    end

    describe 'request to grape app w/param' do
      subject(:response) { get '/grape/hello/7' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/grape/hello/:id')

          break
        end
      end
    end

    describe 'request to rails app' do
      subject(:response) { get '/rails/hello/world' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/rails/hello/world')

          break
        end
      end
    end

    describe 'request to rails app w/param' do
      subject(:response) { get '/rails/hello/7' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/rails/hello/:id')

          break
        end
      end
    end
  end

  context 'nested rack routes' do
    include_context 'multi-app'

    describe 'request to nested sinatra app' do
      subject(:response) { get '/rack/sinatra/hello/world' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/rack/sinatra/hello/world')

          break
        end
      end
    end

    describe 'request to nested sinatra app w/param' do
      subject(:response) { get '/rack/sinatra/hello/7' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/rack/sinatra/hello/:id')

          break
        end
      end
    end

    describe 'request to nested grape app' do
      subject(:response) { get '/rack/grape/hello/world' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/rack/grape/hello/world')

          break
        end
      end
    end

    describe 'request to nested grape app w/param' do
      subject(:response) { get '/rack/grape/hello/7' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/rack/grape/hello/:id')

          break
        end
      end
    end

    describe 'request to nested rails app' do
      subject(:response) { get '/rack/rails/hello/world' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/rack/rails/hello/world')

          break
        end
      end
    end

    describe 'request to nested rails app w/param' do
      subject(:response) { get '/rack/rails/hello/7' }

      it do
        is_expected.to be_ok
        spans.each do |span|
          next unless span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST

          expect(span.get_tag('http.route')).to eq('/rack/rails/hello/:id')

          break
        end
      end
    end
  end
end
