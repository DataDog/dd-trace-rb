# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/support/devise_user_mock'

require 'datadog/appsec/contrib/devise/patcher'
require 'datadog/appsec/contrib/devise/patcher/authenticatable_patch'

RSpec.describe Datadog::AppSec::Contrib::Devise::Patcher::AuthenticatablePatch do
  before do
    allow(Datadog).to receive(:logger).and_return(instance_double(Datadog::Core::Logger).as_null_object)
    allow(Datadog).to receive(:configuration).and_return(settings)
  end

  let(:settings) { Datadog::Core::Configuration::Settings.new }
  # NOTE: This spec needs to be changed to use actual devise controller instead
  let(:mock_controller) do
    Class.new do
      def initialize(success:)
        @success = success
      end

      def validate(resource, &block)
        @success
      end

      prepend Datadog::AppSec::Contrib::Devise::Patcher::AuthenticatablePatch
    end
  end

  context 'when AppSec is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(false)

      settings.appsec.track_user_events.enabled = false
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:controller) { mock_controller.new(success: true) }
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: '00000000-0000-0000-0000-000000000000', email: 'hello@gmail.com', username: 'John'
      )
    end

    it 'does not track successful signin event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_login_success)

      expect(controller.validate(resource)).to eq(true)
    end
  end

  context 'when automated user tracking is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)

      settings.appsec.track_user_events.enabled = true
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:controller) { mock_controller.new(success: true) }
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: '00000000-0000-0000-0000-000000000000', email: 'hello@gmail.com', username: 'John'
      )
    end

    it 'does not track successful signin event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_login_success)

      expect(controller.validate(resource)).to eq(true)
    end
  end

  context 'when AppSec active context is not set' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(nil)

      settings.appsec.track_user_events.enabled = true
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:controller) { mock_controller.new(success: true) }
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: '00000000-0000-0000-0000-000000000000', email: 'hello@gmail.com', username: 'John'
      )
    end

    it 'does not track successful signin event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_login_success)

      expect(controller.validate(resource)).to eq(true)
    end
  end

  context 'when successfully signin via Rememberable strategy' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(active_context)

      settings.appsec.track_user_events.enabled = true
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:active_context) { instance_double(Datadog::AppSec::Context, trace: double, span: double) }
    let(:controller) { mock_controller.new(success: true) }
    let(:mock_controller) do
      Class.new do
        def initialize(success:)
          @result = success
        end

        def validate(resource, &block)
          @result
        end

        prepend Datadog::AppSec::Contrib::Devise::Patcher::AuthenticatablePatch
        prepend Datadog::AppSec::Contrib::Devise::Patcher::RememberablePatch
      end
    end
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: '00000000-0000-0000-0000-000000000000', email: 'hello@gmail.com', username: 'John'
      )
    end

    it 'does not track successful signin event' do
      expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_login_success)

      expect(controller.validate(resource)).to eq(true)
    end
  end

  context 'when authentication is successful' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(active_context)

      settings.appsec.track_user_events.enabled = true
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:active_context) { instance_double(Datadog::AppSec::Context, trace: double, span: double) }
    let(:controller) { mock_controller.new(success: true) }
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: '00000000-0000-0000-0000-000000000000', email: 'hello@gmail.com', username: 'John'
      )
    end

    context 'when user resource was found and has an ID' do
      context 'when tracking mode set to safe' do
        before { settings.appsec.track_user_events.mode = 'safe' }

        it 'tracks successful signin event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_success)
            .with(
              active_context.trace,
              active_context.span,
              user_id: '00000000-0000-0000-0000-000000000000',
              **{}
            )

          expect(controller.validate(resource)).to eq(true)
        end
      end

      context 'when tracking mode set to extended' do
        before { settings.appsec.track_user_events.mode = 'extended' }

        it 'tracks successful signin event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_success)
            .with(
              active_context.trace,
              active_context.span,
              user_id: '00000000-0000-0000-0000-000000000000',
              **{ username: 'John', email: 'hello@gmail.com' }
            )

          expect(controller.validate(resource)).to eq(true)
        end
      end
    end

    context 'when user resource was found, but has no ID' do
      let(:resource) do
        Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
          id: nil, email: 'hello@gmail.com', username: 'John'
        )
      end

      context 'when tracking mode set to safe' do
        before { settings.appsec.track_user_events.mode = 'safe' }

        it 'tracks successful signin event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_success)
            .with(
              active_context.trace,
              active_context.span,
              user_id: nil,
              **{}
            )

          expect(controller.validate(resource)).to eq(true)
        end
      end

      context 'when tracking mode set to extended' do
        before { settings.appsec.track_user_events.mode = 'extended' }

        it 'tracks successful signin event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_success)
            .with(
              active_context.trace,
              active_context.span,
              user_id: nil,
              **{ username: 'John', email: 'hello@gmail.com' }
            )

          expect(controller.validate(resource)).to eq(true)
        end
      end
    end
  end

  context 'when authentication is unsuccessful' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(active_context)

      settings.appsec.track_user_events.enabled = true
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:active_context) { instance_double(Datadog::AppSec::Context, trace: double, span: double) }
    let(:controller) { mock_controller.new(success: false) }
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: '00000000-0000-0000-0000-000000000000', email: 'hello@gmail.com', username: 'John'
      )
    end

    context 'when user resource was found' do
      context 'when tracking mode set to safe' do
        before { settings.appsec.track_user_events.mode = 'safe' }

        it 'tracks unsuccessful signin event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_failure)
            .with(
              active_context.trace,
              active_context.span,
              user_id: '00000000-0000-0000-0000-000000000000',
              user_exists: true,
              **{}
            )

          expect(controller.validate(resource)).to eq(false)
        end
      end

      context 'when tracking mode set to extended' do
        before { settings.appsec.track_user_events.mode = 'extended' }

        it 'tracks unsuccessful signin event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_failure)
            .with(
              active_context.trace,
              active_context.span,
              user_id: '00000000-0000-0000-0000-000000000000',
              user_exists: true,
              **{ username: 'John', email: 'hello@gmail.com' }
            )

          expect(controller.validate(resource)).to eq(false)
        end
      end
    end

    context 'when user resource was not found' do
      context 'when tracking mode set to safe' do
        before { settings.appsec.track_user_events.mode = 'safe' }

        it 'tracks unsuccessful signin event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_failure)
            .with(
              active_context.trace,
              active_context.span,
              user_id: nil,
              user_exists: false,
              **{}
            )

          expect(controller.validate(nil)).to eq(false)
        end
      end

      context 'when tracking mode set to extended' do
        before { settings.appsec.track_user_events.mode = 'extended' }

        it 'tracks unsuccessful signin event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_login_failure)
            .with(
              active_context.trace,
              active_context.span,
              user_id: nil,
              user_exists: false,
              **{}
            )

          expect(controller.validate(nil)).to eq(false)
        end
      end
    end
  end
end
