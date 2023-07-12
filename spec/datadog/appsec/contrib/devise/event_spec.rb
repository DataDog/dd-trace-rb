require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/devise/resource'
require 'datadog/appsec/contrib/devise/event'

RSpec.describe Datadog::AppSec::Contrib::Devise::Event do
  let(:event) { described_class.new(resource, mode) }
  let(:resource) { Datadog::AppSec::Contrib::Devise::Resource.new(object) }

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

  context 'without resource' do
    let(:resource) { nil }
    let(:mode) { 'safe' }

    it do
      expect(event.to_h).to eq({})
    end
  end

  context 'safe mode' do
    let(:mode) { 'safe' }

    context 'with ID but not UUID' do
      let(:object) { object_class.new(id: 1234) }

      it do
        expect(event.user_id).to be_nil
      end
    end

    context 'with ID as UUID' do
      let(:uuid) { '123e4567-e89b-12d3-a456-426655440000' }
      let(:object) { object_class.new(uuid: uuid) }

      it do
        expect(event.user_id).to eq(uuid)
      end
    end
  end

  context 'extended mode' do
    let(:mode) { 'extended' }

    context 'ID' do
      context 'with ID but not UUID' do
        let(:object) { object_class.new(id: 1234) }

        it do
          expect(event.user_id).to eq(1234)
        end
      end

      context 'with ID as UUID' do
        let(:uuid) { '123e4567-e89b-12d3-a456-426655440000' }
        let(:object) { object_class.new(uuid: uuid) }

        it do
          expect(event.user_id).to eq(uuid)
        end
      end
    end

    context 'Email and username' do
      let(:object) { object_class.new(id: 1234, email: 'foo@test.com', username: 'John') }

      it do
        expect(event.to_h).to eq({ email: 'foo@test.com', username: 'John' })
      end
    end
  end

  context 'invalid mode' do
    let(:object) { object_class.new(id: 1234) }
    let(:mode) { 'invalid' }

    it do
      expect(Datadog.logger).to receive(:warn)
      expect(event.to_h).to eq({})
    end
  end
end
