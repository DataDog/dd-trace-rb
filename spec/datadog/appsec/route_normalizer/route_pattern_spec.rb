# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/route_normalizer/route_pattern'

RSpec.describe Datadog::AppSec::RouteNormalizer::RoutePattern do
  describe '#normalize' do
    context 'when route is root' do
      it { expect(described_class.new('/').normalize).to eq('/') }
    end

    context 'when route is static' do
      it { expect(described_class.new('/users').normalize).to eq('/users') }
    end

    context 'when route has multiple static segments' do
      it { expect(described_class.new('/api/v1/health').normalize).to eq('/api/v1/health') }
    end

    context 'when route has trailing slash' do
      it { expect(described_class.new('/users/').normalize).to eq('/users/') }
    end

    context 'when route has no leading slash' do
      it { expect(described_class.new('users/:id').normalize).to eq('/users/{id}') }
    end

    context 'with named params' do
      it { expect(described_class.new('/users/:id').normalize).to eq('/users/{id}') }
      it { expect(described_class.new('/api/:version/users/:id').normalize).to eq('/api/{version}/users/{id}') }
      it { expect(described_class.new('/:a/:b/:c').normalize).to eq('/{a}/{b}/{c}') }
    end

    context 'with glob params' do
      it { expect(described_class.new('/files/*path').normalize).to eq('/files/{path}') }
      it { expect(described_class.new('/*path').normalize).to eq('/{path}') }
    end

    context 'with nameless globs' do
      it { expect(described_class.new('/files/*').normalize).to eq('/files/{param1}') }
      it { expect(described_class.new('/download/*.*').normalize).to eq('/download/{param1+param2}') }
      it { expect(described_class.new('/a/*/b/*').normalize).to eq('/a/{param1}/b/{param2}') }
    end

    context 'with multiple params in one segment' do
      it { expect(described_class.new('/photos/:id.:format').normalize).to eq('/photos/{id+format}') }
      it { expect(described_class.new('/:a.:b.:c').normalize).to eq('/{a+b+c}') }
    end

    context 'with nameless glob before named param' do
      it { expect(described_class.new('/files/*.:format').normalize).to eq('/files/{param1+format}') }
    end

    context 'with mixed static and dynamic' do
      it { expect(described_class.new('/users/user-:id').normalize).to eq('/users/{id}') }
      it { expect(described_class.new('/prefix-:name-suffix').normalize).to eq('/{name}') }
    end

    context 'with static encoding' do
      it { expect(described_class.new('/hello world').normalize).to eq('/hello%20world') }
      it { expect(described_class.new('/café').normalize).to eq('/caf%C3%A9') }
      it { expect(described_class.new('/a+b').normalize).to eq('/a%2Bb') }
      it { expect(described_class.new('/search?').normalize).to eq('/search%3F') }
      it { expect(described_class.new('/file.name~backup').normalize).to eq('/file.name~backup') }
      it { expect(described_class.new('/a-b_c.d~e').normalize).to eq('/a-b_c.d~e') }
    end

    context 'with optional groups (Rails syntax)' do
      it { expect(described_class.new('/posts(/:id)').normalize).to eq('/posts/{id}') }
      it { expect(described_class.new('/posts/:id(.:format)').normalize).to eq('/posts/{id+format}') }
      it { expect(described_class.new('/posts(/:year(/:month(/:day)))').normalize).to eq('/posts/{year}/{month}/{day}') }
      it { expect(described_class.new('/books(/:category)(.:format)').normalize).to eq('/books/{category+format}') }
    end

    context 'with optional groups (Mustermann syntax)' do
      it { expect(described_class.new('/posts(/:id)?').normalize).to eq('/posts/{id}') }
      it { expect(described_class.new('/api/:id(/:action)?').normalize).to eq('/api/{id}/{action}') }
      it { expect(described_class.new('/api/:id(/:action(/:format)?)?').normalize).to eq('/api/{id}/{action}/{format}') }
    end

    context 'when a request path resolves optional groups' do
      it { expect(described_class.new('/posts/:id(.:format)').normalize(path: '/posts/42.json')).to eq('/posts/{id+format}') }
      it { expect(described_class.new('/posts/:id(.:format)').normalize(path: '/posts/42')).to eq('/posts/{id}') }
      it { expect(described_class.new('/posts/:id(-:slug)').normalize(path: '/posts/42-hello')).to eq('/posts/{id+slug}') }
      it { expect(described_class.new('/posts(/:year(/:month))').normalize(path: '/posts/2024')).to eq('/posts/{year}') }
      it { expect(described_class.new('/posts/:id(.:format)').normalize(path: '/users/42')).to eq('/posts/{id+format}') }
      it { expect(described_class.new('/posts(/:id)/edit').normalize(path: '/posts/edit')).to eq('/posts/edit') }
      it { expect(described_class.new('/files/*path(.:format)').normalize(path: '/files/a.txt')).to eq('/files/{path+format}') }
      it { expect(described_class.new('/posts/:id?').normalize(path: '/posts')).to eq('/posts') }
      it { expect(described_class.new('/a.:b?').normalize(path: '/a')).to eq('/a') }

      it 'lets glob params span to a following segment' do
        expect(
          described_class.new('/books/*section/:title(.:format)').normalize(path: '/books/some/section/last-words.json')
        ).to eq('/books/{section}/{title+format}')
      end

      it { expect(described_class.new('/posts/:id(.:format)').normalize(path: "/posts/#{'a' * 9000}")).to eq('/posts/{id+format}') }
    end

    context 'with Sinatra-style patterns' do
      it { expect(described_class.new('/users/:id').normalize).to eq('/users/{id}') }
      it { expect(described_class.new('/files/*').normalize).to eq('/files/{param1}') }
      it { expect(described_class.new('/download/*.*').normalize).to eq('/download/{param1+param2}') }
      it { expect(described_class.new('/say/*/to/*').normalize).to eq('/say/{param1}/to/{param2}') }
      it { expect(described_class.new('/posts/:id.?:format?').normalize(path: '/posts/1')).to eq('/posts/{id}') }
      it { expect(described_class.new('/posts/:id.?:format?').normalize(path: '/posts/1.json')).to eq('/posts/{id+format}') }
    end

    context 'with Grape-style patterns' do
      it { expect(described_class.new('/api/users/:id').normalize).to eq('/api/users/{id}') }
      it { expect(described_class.new('/api/:version/status').normalize).to eq('/api/{version}/status') }
      it { expect(described_class.new('/api/:id(/:ext)').normalize).to eq('/api/{id}/{ext}') }
    end
  end
end
