require 'ddtrace/contrib/support/spec_helper'
require 'rack/test'

require 'sinatra/base'

require 'ddtrace'
require 'ddtrace/contrib/sinatra/tracer'

RSpec.describe 'Sinatra instrumentation for multi-apps' do
  include Rack::Test::Methods

  let(:options) { {} }

  before do
    Datadog.configure do |c|
      c.use :sinatra, options
    end
  end

  after { Datadog.registry[:sinatra].reset_configuration! }

  shared_context 'multi-app' do
    let(:app) do
      apps_to_build = apps

      Rack::Builder.new do
        apps_to_build.each do |root, app|
          map root do
            run app
          end
        end
      end.to_app
    end

    let(:apps) do
      {
        '/one' => app_one,
        '/two' => app_two
      }
    end

    let(:app_one) do
      Class.new(Sinatra::Application) do
        get '/endpoint' do
          '1'
        end
      end
    end

    let(:app_two) do
      Class.new(Sinatra::Application) do
        get '/endpoint' do
          '2'
        end
      end
    end
  end

  context 'with script names' do
    include_context 'multi-app'
    let(:options) { super().merge(resource_script_names: use_script_names) }

    context 'disabled' do
      let(:use_script_names) { false }

      describe 'request to first app' do
        subject(:response) { get '/one/endpoint' }

        it do
          is_expected.to be_ok
          expect(spans).to have(2).items
          spans.each do |span|
            expect(span.resource).to eq('GET /endpoint')
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_ROUTE_PATH)).to eq('/endpoint')
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_SCRIPT_NAME)).to eq('/one')
          end
        end
      end

      describe 'request to second app' do
        subject(:response) { get '/two/endpoint' }

        it do
          is_expected.to be_ok
          expect(spans).to have(2).items
          spans.each do |span|
            expect(span.resource).to eq('GET /endpoint')
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_ROUTE_PATH)).to eq('/endpoint')
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_SCRIPT_NAME)).to eq('/two')
          end
        end
      end
    end

    context 'enabled' do
      let(:use_script_names) { true }

      describe 'request to first app' do
        subject(:response) { get '/one/endpoint' }

        it do
          is_expected.to be_ok
          expect(spans).to have(2).items
          spans.each do |span|
            expect(span.resource).to eq('GET /one/endpoint')
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_ROUTE_PATH)).to eq('/one/endpoint')
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_SCRIPT_NAME)).to eq('/one')
          end
        end
      end

      describe 'request to second app' do
        subject(:response) { get '/two/endpoint' }

        it do
          is_expected.to be_ok
          expect(spans).to have(2).items
          spans.each do |span|
            expect(span.resource).to eq('GET /two/endpoint')
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_ROUTE_PATH)).to eq('/two/endpoint')
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_SCRIPT_NAME)).to eq('/two')
          end
        end
      end
    end
  end
end
