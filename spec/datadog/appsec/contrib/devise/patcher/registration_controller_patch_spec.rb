require 'datadog/appsec/spec_helper'

require 'securerandom'
require 'datadog/appsec/contrib/devise/patcher'
require 'datadog/appsec/contrib/devise/patcher/registration_controller_patch'

RSpec.describe Datadog::AppSec::Contrib::Devise::Patcher::RegistrationControllerPatch do
  let(:mock_controller) do
    Class.new do
      prepend Datadog::AppSec::Contrib::Devise::Patcher::RegistrationControllerPatch

      def initialize(result, resource)
        @resource = resource
        @result = result
      end

      def create
        yield @resource if block_given?
        @result
      end
    end
  end

  let(:mock_resource) do
    Class.new do
      attr_reader :id, :email, :username, :persisted

      def initialize(id, email, username, persisted)
        @id = id
        @email = email
        @username = username
        @persisted = persisted
      end

      def persisted?
        @persisted
      end

      def try(value)
        send(value)
      end
    end
  end

  let(:non_persisted_resource) { mock_resource.new(nil, nil, nil, false) }
  let(:persited_resource) { mock_resource.new(SecureRandom.uuid, 'hello@gmail.com', 'John', true) }
  let(:automated_track_user_events) { double(enabled: track_user_events_enabled, mode: mode) }
  let(:controller) { mock_controller.new(true, resource) }

  let(:resource) { non_persisted_resource }

  before do
    expect(Datadog::AppSec).to receive(:enabled?).and_return(appsec_enabled)
    if appsec_enabled
      expect(Datadog.configuration.appsec).to receive(:track_user_events).and_return(automated_track_user_events)

      expect(Datadog::AppSec).to receive(:active_scope).and_return(appsec_scope) if track_user_events_enabled
    end
  end

  context 'AppSec disabled' do
    let(:appsec_enabled) { false }
    let(:track_user_events_enabled) { false }

    it 'do not tracks event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
      expect(controller.create).to eq(true)
    end

    context 'and a block is given' do
      let(:canary) { proc { |resource| } }
      let(:block) { proc { |resource| canary.call(resource) } }

      it 'do not tracks event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
        expect(canary).to receive(:call).with(resource)
        expect(controller.create(&block)).to eq(true)
      end
    end
  end

  context 'Automated user tracking is disabled' do
    let(:appsec_enabled) { true }
    let(:track_user_events_enabled) { false }
    let(:mode) { 'safe' }

    it 'do not tracks event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
      expect(controller.create).to eq(true)
    end

    context 'and a block is given' do
      let(:canary) { proc { |resource| } }
      let(:block) { proc { |resource| canary.call(resource) } }

      it 'do not tracks event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
        expect(canary).to receive(:call).with(resource)
        expect(controller.create(&block)).to eq(true)
      end
    end
  end

  context 'AppSec scope is nil ' do
    let(:appsec_enabled) { true }
    let(:track_user_events_enabled) { true }
    let(:mode) { 'safe' }
    let(:appsec_scope) { nil }

    it 'do not tracks event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
      expect(controller.create).to eq(true)
    end

    context 'and a block is given' do
      let(:canary) { proc { |resource| } }
      let(:block) { proc { |resource| canary.call(resource) } }

      it 'do not tracks event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
        expect(canary).to receive(:call).with(resource)
        expect(controller.create(&block)).to eq(true)
      end
    end
  end

  context 'with persisted resource' do
    let(:appsec_enabled) { true }
    let(:track_user_events_enabled) { true }
    let(:appsec_scope) { instance_double(Datadog::AppSec::Scope, trace: double, service_entry_span: double) }

    context 'with resource ID' do
      let(:resource) { persited_resource }

      context 'and a block is given' do
        let(:canary) { proc { |resource| } }
        let(:block) { proc { |resource| canary.call(resource) } }

        context 'safe mode' do
          let(:mode) { 'safe' }

          it 'tracks event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup).with(
              appsec_scope.trace,
              appsec_scope.service_entry_span,
              user_id: resource.id,
              **{}
            )
            expect(canary).to receive(:call).with(resource)
            expect(controller.create(&block)).to eq(true)
          end
        end

        context 'extended mode' do
          let(:mode) { 'extended' }

          it 'tracks event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup).with(
              appsec_scope.trace,
              appsec_scope.service_entry_span,
              user_id: resource.id,
              **{ email: 'hello@gmail.com', username: 'John' }
            )
            expect(canary).to receive(:call).with(resource)
            expect(controller.create(&block)).to eq(true)
          end
        end
      end

      context 'safe mode' do
        let(:mode) { 'safe' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: resource.id,
            **{}
          )
          expect(controller.create).to eq(true)
        end
      end

      context 'extended mode' do
        let(:mode) { 'extended' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: resource.id,
            **{ email: 'hello@gmail.com', username: 'John' }
          )
          expect(controller.create).to eq(true)
        end
      end
    end

    context 'without resource ID' do
      let(:resource) { mock_resource.new(nil, 'hello@gmail.com', 'John', true) }

      context 'and a block is given' do
        let(:canary) { proc { |resource| } }
        let(:block) { proc { |resource| canary.call(resource) } }

        context 'safe mode' do
          let(:mode) { 'safe' }

          it 'tracks event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup).with(
              appsec_scope.trace,
              appsec_scope.service_entry_span,
              user_id: nil,
              **{}
            )
            expect(canary).to receive(:call).with(resource)
            expect(controller.create(&block)).to eq(true)
          end
        end

        context 'extended mode' do
          let(:mode) { 'extended' }

          it 'tracks event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup).with(
              appsec_scope.trace,
              appsec_scope.service_entry_span,
              user_id: nil,
              **{ email: 'hello@gmail.com', username: 'John' }
            )
            expect(canary).to receive(:call).with(resource)
            expect(controller.create(&block)).to eq(true)
          end
        end
      end

      context 'safe mode' do
        let(:mode) { 'safe' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: nil,
            **{}
          )
          expect(controller.create).to eq(true)
        end
      end

      context 'extended mode' do
        let(:mode) { 'extended' }

        it 'tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup).with(
            appsec_scope.trace,
            appsec_scope.service_entry_span,
            user_id: nil,
            **{ email: 'hello@gmail.com', username: 'John' }
          )
          expect(controller.create).to eq(true)
        end
      end
    end
  end

  context 'with non persisted resource' do
    let(:appsec_enabled) { true }
    let(:track_user_events_enabled) { true }
    let(:appsec_scope) { instance_double(Datadog::AppSec::Scope, trace: double, service_entry_span: double) }
    let(:resource) { non_persisted_resource }

    context 'safe mode' do
      let(:mode) { 'safe' }

      it 'do not tracks event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
        expect(controller.create).to eq(true)
      end

      context 'and a block is given' do
        let(:canary) { proc { |resource| } }
        let(:block) { proc { |resource| canary.call(resource) } }

        it 'do not tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
          expect(canary).to receive(:call).with(resource)
          expect(controller.create(&block)).to eq(true)
        end
      end
    end

    context 'extended mode' do
      let(:mode) { 'extended' }

      it 'tracks event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
        expect(controller.create).to eq(true)
      end

      context 'and a block is given' do
        let(:canary) { proc { |resource| } }
        let(:block) { proc { |resource| canary.call(resource) } }

        it 'do not tracks event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
          expect(canary).to receive(:call).with(resource)
          expect(controller.create(&block)).to eq(true)
        end
      end
    end
  end
end
