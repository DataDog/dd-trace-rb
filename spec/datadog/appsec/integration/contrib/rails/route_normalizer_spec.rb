# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'

require 'action_dispatch'
require 'datadog/appsec/route_normalizer/rails_journey_route'

RSpec.describe Datadog::AppSec::RouteNormalizer::RailsJourneyRoute do
  def build_route(path_spec)
    route_set = ActionDispatch::Routing::RouteSet.new
    route_set.draw { get path_spec, to: 'test#show' }
    route_set.routes.first
  end

  def normalize(path_spec, path_params, request_path)
    route = build_route(path_spec)
    described_class.new(path_params, request_path, route: route).normalize
  end

  describe '#normalize' do
    context 'when route is static' do
      it { expect(normalize('/health', {}, '/health')).to eq('/health') }
    end

    context 'when route has a single named param' do
      it { expect(normalize('/users/:id', {id: '42'}, '/users/42')).to eq('/users/{id}') }
    end

    context 'when route has multiple named params' do
      it 'normalizes each param independently' do
        expect(normalize(
          '/users/:user_id/posts/:id',
          {user_id: '42', id: '7'},
          '/users/42/posts/7',
        )).to eq('/users/{user_id}/posts/{id}')
      end
    end

    context 'when route has optional format present in URL' do
      it { expect(normalize('/posts/:id(.:format)', {id: '1', format: 'json'}, '/posts/1.json')).to eq('/posts/{id+format}') }
    end

    context 'when route has optional format absent from URL' do
      it { expect(normalize('/posts/:id(.:format)', {id: '1', format: nil}, '/posts/1')).to eq('/posts/{id}') }
    end

    context 'when route has optional format as Symbol default' do
      it { expect(normalize('/posts/:id(.:format)', {id: '1', format: :json}, '/posts/1')).to eq('/posts/{id}') }
    end

    context 'when route has optional format as String default not in URL' do
      it { expect(normalize('/posts/:id(.:format)', {id: '1', format: 'json'}, '/posts/1')).to eq('/posts/{id}') }
    end

    context 'when route has nested optionals with all present' do
      it 'includes all optional segments' do
        expect(normalize(
          '/archive(/:year(/:month(/:day)))',
          {year: '2024', month: '01', day: '15'},
          '/archive/2024/01/15',
        )).to eq('/archive/{year}/{month}/{day}')
      end
    end

    context 'when route has nested optionals with only year' do
      it { expect(normalize('/archive(/:year(/:month(/:day)))', {year: '2024'}, '/archive/2024')).to eq('/archive/{year}') }
    end

    context 'when route has nested optionals with none present' do
      it { expect(normalize('/archive(/:year(/:month(/:day)))', {}, '/archive')).to eq('/archive') }
    end

    context 'when route has mandatory multi-param segment' do
      it { expect(normalize('/photos/:id.:format', {id: '1', format: 'json'}, '/photos/1.json')).to eq('/photos/{id+format}') }
    end

    context 'when route has glob param' do
      it { expect(normalize('/files/*path', {path: 'a/b/c'}, '/files/a/b/c')).to eq('/files/{path}') }
    end

    context 'when route has mixed static and dynamic text' do
      it { expect(normalize('/mixed/user-:id', {id: '42'}, '/mixed/user-42')).to eq('/mixed/{id}') }
    end

    context 'when route is root' do
      it { expect(normalize('/', {}, '/')).to eq('/') }
    end
  end

  describe '#normalize with route_string' do
    def normalize_string(route_string, path_params, request_path)
      described_class.new(path_params, request_path, route_string: route_string).normalize
    end

    context 'when route has optional format present in URL' do
      it { expect(normalize_string('/posts/:id(.:format)', {id: '1', format: 'json'}, '/posts/1.json')).to eq('/posts/{id+format}') }
    end

    context 'when route has optional format absent from URL' do
      it { expect(normalize_string('/posts/:id(.:format)', {id: '1', format: nil}, '/posts/1')).to eq('/posts/{id}') }
    end

    context 'when route has nested optionals' do
      it { expect(normalize_string('/archive(/:year(/:month))', {year: '2024'}, '/archive/2024')).to eq('/archive/{year}') }
    end
  end
end
