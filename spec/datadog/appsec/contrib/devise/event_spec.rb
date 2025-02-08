# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/support/devise_user_mock'

require 'datadog/appsec/contrib/devise/resource'
require 'datadog/appsec/contrib/devise/event'

RSpec.describe Datadog::AppSec::Contrib::Devise::Event do
  let(:event) { described_class.new(resource, mode) }
  let(:resource) { Datadog::AppSec::Contrib::Devise::Resource.new(object) }

  describe '#to_h' do
    context 'when resource is nil' do
      let(:event) { described_class.new(nil, 'identification') }

      it { expect(event.to_h).to eq({}) }
    end

    context 'when mode is invalid' do
      let(:event) { described_class.new(resource, 'invalid') }
      let(:resource) { Datadog::AppSec::Contrib::Support::DeviseUserMock.new(id: 1234) }

      it 'writes warning log message' do
        expect(Datadog.logger).to receive(:warn)
        expect(event.to_h).to eq({})
      end
    end

    context 'when mode is identification and different resource attributes present' do
      let(:event) { described_class.new(resource, 'identification') }
      let(:resource) do
        Datadog::AppSec::Contrib::Support::DeviseUserMock.new(id: 1234, email: 'foo@test.com', username: 'John')
      end

      it { expect(event.to_h).to eq({ email: 'foo@test.com', username: 'John' }) }
    end
  end

  describe '#user_id' do
    context 'when mode is anonymization and ID is not UUID-like' do
      let(:event) { described_class.new(resource, 'anonymization') }
      let(:resource) { Datadog::AppSec::Contrib::Support::DeviseUserMock.new(id: 1234) }

      it { expect(event.user_id).to be_nil }
    end

    context 'when mode is anonymization and ID is UUID-like' do
      let(:event) { described_class.new(resource, 'anonymization') }
      let(:resource) { Datadog::AppSec::Contrib::Support::DeviseUserMock.new(id: '00000000-0000-0000-0000-000000000000') }

      it { expect(event.user_id).to eq('00000000-0000-0000-0000-000000000000') }
    end

    context 'when mode is identification and ID is not UUID-like' do
      let(:event) { described_class.new(resource, 'identification') }
      let(:resource) { Datadog::AppSec::Contrib::Support::DeviseUserMock.new(id: 1234) }

      it { expect(event.user_id).to eq(1234) }
    end

    context 'when mode is identification and ID is UUID-like' do
      let(:event) { described_class.new(resource, 'identification') }
      let(:resource) { Datadog::AppSec::Contrib::Support::DeviseUserMock.new(id: '00000000-0000-0000-0000-000000000000') }

      it { expect(event.user_id).to eq('00000000-0000-0000-0000-000000000000') }
    end
  end
end
