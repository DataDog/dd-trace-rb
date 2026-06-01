# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/route_normalizer'

RSpec.describe Datadog::AppSec::RouteNormalizer::StringRoute do
  describe '#normalized' do
    context 'when route is root' do
      it { expect(described_class.new('/').normalized).to eq('/') }
    end

    context 'when route is static' do
      it { expect(described_class.new('/users').normalized).to eq('/users') }
    end

    context 'when route has multiple static segments' do
      it { expect(described_class.new('/api/v1/health').normalized).to eq('/api/v1/health') }
    end

    context 'when route has trailing slash' do
      it { expect(described_class.new('/users/').normalized).to eq('/users/') }
    end

    context 'when route has no leading slash' do
      it { expect(described_class.new('users/:id').normalized).to eq('/users/{id}') }
    end

    context 'with named params' do
      it { expect(described_class.new('/users/:id').normalized).to eq('/users/{id}') }

      it { expect(described_class.new('/api/:version/users/:id').normalized).to eq('/api/{version}/users/{id}') }

      it { expect(described_class.new('/:a/:b/:c').normalized).to eq('/{a}/{b}/{c}') }
    end

    context 'with glob params' do
      it { expect(described_class.new('/files/*path').normalized).to eq('/files/{path}') }

      it { expect(described_class.new('/*path').normalized).to eq('/{path}') }
    end

    context 'with nameless globs' do
      it { expect(described_class.new('/files/*').normalized).to eq('/files/{param1}') }

      it { expect(described_class.new('/download/*.*').normalized).to eq('/download/{param1+param2}') }

      it { expect(described_class.new('/a/*/b/*').normalized).to eq('/a/{param1}/b/{param2}') }
    end

    context 'with multiple params in one segment' do
      it { expect(described_class.new('/photos/:id.:format').normalized).to eq('/photos/{id+format}') }

      it { expect(described_class.new('/:a.:b.:c').normalized).to eq('/{a+b+c}') }
    end

    context 'with nameless glob before named param' do
      it { expect(described_class.new('/files/*.:format').normalized).to eq('/files/{param1+format}') }
    end

    context 'with mixed static and dynamic' do
      it { expect(described_class.new('/users/user-:id').normalized).to eq('/users/{id}') }

      it { expect(described_class.new('/prefix-:name-suffix').normalized).to eq('/{name}') }
    end

    context 'with static encoding' do
      it { expect(described_class.new('/hello world').normalized).to eq('/hello%20world') }

      it { expect(described_class.new('/café').normalized).to eq('/caf%C3%A9') }

      it { expect(described_class.new('/a+b').normalized).to eq('/a%2Bb') }

      it { expect(described_class.new('/file.name~backup').normalized).to eq('/file.name~backup') }

      it { expect(described_class.new('/a-b_c.d~e').normalized).to eq('/a-b_c.d~e') }
    end

    context 'with optional groups (Rails syntax)' do
      it { expect(described_class.new('/posts(/:id)').normalized).to eq('/posts/{id}') }

      it { expect(described_class.new('/posts/:id(.:format)').normalized).to eq('/posts/{id+format}') }

      it { expect(described_class.new('/posts(/:year(/:month(/:day)))').normalized).to eq('/posts/{year}/{month}/{day}') }

      it { expect(described_class.new('/books(/:category)(.:format)').normalized).to eq('/books/{category+format}') }
    end

    context 'with optional groups (Mustermann syntax)' do
      it { expect(described_class.new('/posts(/:id)?').normalized).to eq('/posts/{id}') }

      it { expect(described_class.new('/api/:id(/:action)?').normalized).to eq('/api/{id}/{action}') }

      it { expect(described_class.new('/api/:id(/:action(/:format)?)?').normalized).to eq('/api/{id}/{action}/{format}') }
    end

    context 'when a request path resolves optional groups' do
      it { expect(described_class.new('/posts/:id(.:format)').normalized(for_path: '/posts/42.json')).to eq('/posts/{id+format}') }

      it { expect(described_class.new('/posts/:id(.:format)').normalized(for_path: '/posts/42')).to eq('/posts/{id}') }

      it { expect(described_class.new('/posts(/:year(/:month))').normalized(for_path: '/posts/2024')).to eq('/posts/{year}') }
    end

    context 'with Sinatra-style patterns' do
      it { expect(described_class.new('/users/:id').normalized).to eq('/users/{id}') }

      it { expect(described_class.new('/files/*').normalized).to eq('/files/{param1}') }

      it { expect(described_class.new('/download/*.*').normalized).to eq('/download/{param1+param2}') }

      it { expect(described_class.new('/say/*/to/*').normalized).to eq('/say/{param1}/to/{param2}') }
    end

    context 'with Grape-style patterns' do
      it { expect(described_class.new('/api/users/:id').normalized).to eq('/api/users/{id}') }

      it { expect(described_class.new('/api/:version/status').normalized).to eq('/api/{version}/status') }

      it { expect(described_class.new('/api/:id(/:ext)').normalized).to eq('/api/{id}/{ext}') }
    end
  end
end
