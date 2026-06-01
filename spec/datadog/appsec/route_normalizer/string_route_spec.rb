# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/route_normalizer'

RSpec.describe Datadog::AppSec::RouteNormalizer::StringRoute do
  describe '#normalize' do
    subject(:result) { described_class.normalize(route_string).normalize }

    context 'when route is root' do
      it { expect(described_class.normalize('/')).to eq('/') }
    end

    context 'when route is static' do
      it { expect(described_class.normalize('/users')).to eq('/users') }
    end

    context 'when route has multiple static segments' do
      it { expect(described_class.normalize('/api/v1/health')).to eq('/api/v1/health') }
    end

    context 'when route has trailing slash' do
      it { expect(described_class.normalize('/users/')).to eq('/users/') }
    end

    context 'when route has no leading slash' do
      it { expect(described_class.normalize('users/:id')).to eq('/users/{id}') }
    end

    context 'with named params' do
      it { expect(described_class.normalize('/users/:id')).to eq('/users/{id}') }

      it { expect(described_class.normalize('/api/:version/users/:id')).to eq('/api/{version}/users/{id}') }

      it { expect(described_class.normalize('/:a/:b/:c')).to eq('/{a}/{b}/{c}') }
    end

    context 'with glob params' do
      it { expect(described_class.normalize('/files/*path')).to eq('/files/{path}') }

      it { expect(described_class.normalize('/*path')).to eq('/{path}') }
    end

    context 'with nameless globs' do
      it { expect(described_class.normalize('/files/*')).to eq('/files/{param1}') }

      it { expect(described_class.normalize('/download/*.*')).to eq('/download/{param1+param2}') }

      it { expect(described_class.normalize('/a/*/b/*')).to eq('/a/{param1}/b/{param2}') }
    end

    context 'with multiple params in one segment' do
      it { expect(described_class.normalize('/photos/:id.:format')).to eq('/photos/{id+format}') }

      it { expect(described_class.normalize('/:a.:b.:c')).to eq('/{a+b+c}') }
    end

    context 'with nameless glob before named param' do
      it { expect(described_class.normalize('/files/*.:format')).to eq('/files/{param1+format}') }
    end

    context 'with mixed static and dynamic' do
      it { expect(described_class.normalize('/users/user-:id')).to eq('/users/{id}') }

      it { expect(described_class.normalize('/prefix-:name-suffix')).to eq('/{name}') }
    end

    context 'with static encoding' do
      it { expect(described_class.normalize('/hello world')).to eq('/hello%20world') }

      it { expect(described_class.normalize('/café')).to eq('/caf%C3%A9') }

      it { expect(described_class.normalize('/a+b')).to eq('/a%2Bb') }

      it { expect(described_class.normalize('/file.name~backup')).to eq('/file.name~backup') }

      it { expect(described_class.normalize('/a-b_c.d~e')).to eq('/a-b_c.d~e') }
    end

    context 'with optional groups (Rails syntax)' do
      it { expect(described_class.normalize('/posts(/:id)')).to eq('/posts/{id}') }

      it { expect(described_class.normalize('/posts/:id(.:format)')).to eq('/posts/{id+format}') }

      it { expect(described_class.normalize('/posts(/:year(/:month(/:day)))')).to eq('/posts/{year}/{month}/{day}') }

      it { expect(described_class.normalize('/books(/:category)(.:format)')).to eq('/books/{category+format}') }
    end

    context 'with optional groups (Mustermann syntax)' do
      it { expect(described_class.normalize('/posts(/:id)?')).to eq('/posts/{id}') }

      it { expect(described_class.normalize('/api/:id(/:action)?')).to eq('/api/{id}/{action}') }

      it { expect(described_class.normalize('/api/:id(/:action(/:format)?)?')).to eq('/api/{id}/{action}/{format}') }
    end

    context 'with Sinatra-style patterns' do
      it { expect(described_class.normalize('/users/:id')).to eq('/users/{id}') }

      it { expect(described_class.normalize('/files/*')).to eq('/files/{param1}') }

      it { expect(described_class.normalize('/download/*.*')).to eq('/download/{param1+param2}') }

      it { expect(described_class.normalize('/say/*/to/*')).to eq('/say/{param1}/to/{param2}') }
    end

    context 'with Grape-style patterns' do
      it { expect(described_class.normalize('/api/users/:id')).to eq('/api/users/{id}') }

      it { expect(described_class.normalize('/api/:version/status')).to eq('/api/{version}/status') }

      it { expect(described_class.normalize('/api/:id(/:ext)')).to eq('/api/{id}/{ext}') }
    end
  end

  describe '.encode_static' do
    it { expect(described_class.encode_static('users')).to eq('users') }

    it { expect(described_class.encode_static('hello world')).to eq('hello%20world') }

    it { expect(described_class.encode_static('café')).to eq('caf%C3%A9') }

    it { expect(described_class.encode_static('/users/path')).to eq('/users/path') }

    it { expect(described_class.encode_static('a-b_c.d~e')).to eq('a-b_c.d~e') }

    it { expect(described_class.encode_static('a+b')).to eq('a%2Bb') }

    it { expect(described_class.encode_static('')).to eq('') }
  end
end
