require 'datadog/appsec/spec_helper'
require 'securerandom'
require 'datadog/appsec/contrib/devise/resource'

RSpec.describe Datadog::AppSec::Contrib::Devise::Resource do
  subject(:resource) { described_class.new(object) }

  let(:object_class) do
    Class.new do
      attr_reader :id, :uuid, :email, :username

      def initialize(id: nil, uuid: nil, email: nil, username: nil)
        @id = id
        @uuid = uuid
        @email = email
        @username = username
      end
    end
  end

  let(:empty_class) do
    Class.new {}
  end

  describe '#id' do
    context 'resource respond to id' do
      let(:object) { object_class.new(id: 1) }

      it 'returns id' do
        expect(resource.id).to eq(1)
      end
    end

    context 'resource respond to uuid' do
      let(:uuid) { SecureRandom.uuid }
      let(:object) { object_class.new(uuid: uuid) }

      it 'returns id' do
        expect(resource.id).to eq(uuid)
      end
    end

    context 'resource respond to id and uuid' do
      let(:uuid) { SecureRandom.uuid }
      let(:object) { object_class.new(id: 1, uuid: uuid) }

      it 'returns id' do
        expect(resource.id).to eq(1)
      end
    end

    context 'resource does not respond to id or uuid' do
      let(:uuid) { SecureRandom.uuid }
      let(:object) { empty_class.new }

      it 'returns nil' do
        expect(resource.id).to be_nil
      end
    end
  end

  describe '#email' do
    context 'resource respond to email' do
      let(:object) { object_class.new(email: 'hello@gmail.com') }

      it 'returns email' do
        expect(resource.email).to eq('hello@gmail.com')
      end
    end

    context 'resource do not respond to email' do
      let(:object) { empty_class.new }

      it 'returns nil' do
        expect(resource.email).to be_nil
      end
    end
  end

  describe '#username' do
    context 'resource respond to username' do
      let(:object) { object_class.new(username: 'Joe') }

      it 'returns email' do
        expect(resource.username).to eq('Joe')
      end
    end

    context 'resource do not respond to username' do
      let(:object) { empty_class.new }

      it 'returns nil' do
        expect(resource.username).to be_nil
      end
    end
  end
end
