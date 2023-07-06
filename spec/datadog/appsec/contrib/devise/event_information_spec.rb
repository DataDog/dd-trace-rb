require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/devise/resource'
require 'datadog/appsec/contrib/devise/event_information'

RSpec.describe Datadog::AppSec::Contrib::Devise::EventInformation do
  subject(:event_information) { described_class.extract(resource, mode) }
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

    it { is_expected.to eq({}) }
  end

  context 'safe mode' do
    let(:mode) { 'safe' }

    context 'with ID but not UUID' do
      let(:object) { object_class.new(id: 1234) }

      it { is_expected.to eq({}) }
    end

    context 'with ID as UUID' do
      let(:uuid) { '123e4567-e89b-12d3-a456-426655440000' }
      let(:object) { object_class.new(uuid: uuid) }

      it { is_expected.to eq({ id: uuid }) }
    end
  end

  context 'extended mode' do
    let(:mode) { 'extended' }

    context 'ID' do
      context 'with ID but not UUID' do
        let(:object) { object_class.new(id: 1234) }

        it { is_expected.to eq({ id: 1234 }) }
      end

      context 'with ID as UUID' do
        let(:uuid) { '123e4567-e89b-12d3-a456-426655440000' }
        let(:object) { object_class.new(uuid: uuid) }

        it { is_expected.to eq({ id: uuid }) }
      end
    end

    context 'Email and username' do
      let(:object) { object_class.new(id: 1234, email: 'foo@test.com', username: 'John') }

      it { is_expected.to eq({ email: 'foo@test.com', id: 1234, username: 'John' }) }
    end
  end

  context 'invalid mode' do
    let(:object) { object_class.new(id: 1234) }
    let(:mode) { 'invalid' }

    it do
      expect(Datadog.logger).to receive(:warn)
      is_expected.to eq({})
    end
  end
end
