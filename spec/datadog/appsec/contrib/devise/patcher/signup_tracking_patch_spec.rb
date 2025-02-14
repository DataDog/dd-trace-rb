# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/support/devise_user_mock'

require 'datadog/appsec/contrib/devise/patcher'
require 'datadog/appsec/contrib/devise/patcher/signup_tracking_patch'

RSpec.describe Datadog::AppSec::Contrib::Devise::Patcher::SignupTrackingPatch do
  before do
    allow(Datadog).to receive(:logger).and_return(instance_double(Datadog::Core::Logger).as_null_object)
    allow(Datadog).to receive(:configuration).and_return(settings)
  end

  let(:settings) { Datadog::Core::Configuration::Settings.new }
  # NOTE: This spec needs to be changed to use actual devise controller instead
  let(:mock_controller) do
    Class.new do
      prepend Datadog::AppSec::Contrib::Devise::Patcher::SignupTrackingPatch

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

  context 'when AppSec is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(false)

      settings.appsec.track_user_events.enabled = false
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:controller) { mock_controller.new(true, resource) }
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: nil, email: nil, username: nil, persisted: false
      )
    end

    context 'when no block is given to registration controller' do
      it 'does not track signup event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)

        expect(controller.create).to eq(true)
      end
    end

    context 'when block is given to registration controller' do
      let(:canary) { proc { |_resource| } }
      let(:block) { proc { |resource| canary.call(resource) } }

      it 'does not track signup event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
        expect(canary).to receive(:call).with(resource)

        expect(controller.create(&block)).to eq(true)
      end
    end
  end

  context 'when automated user tracking is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)

      settings.appsec.track_user_events.enabled = false
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:controller) { mock_controller.new(true, resource) }
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: nil, email: nil, username: nil, persisted: false
      )
    end

    context 'when no block is given to registration controller' do
      it 'does not track signup event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)

        expect(controller.create).to eq(true)
      end
    end

    context 'when block is given to registration controller' do
      let(:canary) { proc { |_resource| } }
      let(:block) { proc { |resource| canary.call(resource) } }

      it 'does not track signup event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
        expect(canary).to receive(:call).with(resource)

        expect(controller.create(&block)).to eq(true)
      end
    end
  end

  context 'when AppSec active context is not set' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(nil)

      settings.appsec.track_user_events.enabled = true
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:controller) { mock_controller.new(true, resource) }
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: nil, email: nil, username: nil, persisted: false
      )
    end

    context 'when no block is given to registration controller' do
      it 'does not track signup event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)

        expect(controller.create).to eq(true)
      end
    end

    context 'when block is given to registration controller' do
      let(:canary) { proc { |_resource| } }
      let(:block) { proc { |resource| canary.call(resource) } }

      it 'does not track signup event' do
        expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
        expect(canary).to receive(:call).with(resource)

        expect(controller.create(&block)).to eq(true)
      end
    end
  end

  context 'when registration defines current user as persisted resource' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(active_context)

      settings.appsec.track_user_events.enabled = true
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:controller) { mock_controller.new(true, resource) }
    let(:active_context) { instance_double(Datadog::AppSec::Context, trace: double, span: double) }

    context 'when current user has an extractable ID' do
      let(:resource) do
        Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
          id: '00000000-0000-0000-0000-000000000000',
          email: 'hello@gmail.com',
          username: 'John',
          persisted: true
        )
      end

      context 'when no block is given to registration controller' do
        context 'when tracking mode set to safe' do
          before { settings.appsec.track_user_events.mode = 'safe' }

          it 'tracks signup event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup)
              .with(active_context.trace, active_context.span, user_id: resource.id, **{})

            expect(controller.create).to eq(true)
          end
        end

        context 'when tracking mode set to extended' do
          before { settings.appsec.track_user_events.mode = 'extended' }

          it 'tracks signup event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup)
              .with(
                active_context.trace,
                active_context.span,
                user_id: '00000000-0000-0000-0000-000000000000',
                **{ email: 'hello@gmail.com', username: 'John' }
              )

            expect(controller.create).to eq(true)
          end
        end
      end

      context 'when block is given to registration controller' do
        let(:canary) { proc { |_resource| } }
        let(:block) { proc { |resource| canary.call(resource) } }

        context 'when tracking mode set to safe' do
          before { settings.appsec.track_user_events.mode = 'safe' }

          it 'tracks signup event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup)
              .with(
                active_context.trace,
                active_context.span,
                user_id: '00000000-0000-0000-0000-000000000000',
                **{}
              )
            expect(canary).to receive(:call).with(resource)

            expect(controller.create(&block)).to eq(true)
          end
        end

        context 'when tracking mode set to extended' do
          before { settings.appsec.track_user_events.mode = 'extended' }

          it 'tracks signup event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup)
              .with(
                active_context.trace,
                active_context.span,
                user_id: '00000000-0000-0000-0000-000000000000',
                **{ email: 'hello@gmail.com', username: 'John' }
              )
            expect(canary).to receive(:call).with(resource)

            expect(controller.create(&block)).to eq(true)
          end
        end
      end
    end

    context 'when current user does not have an extractable ID' do
      let(:resource) do
        Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
          id: nil, email: 'hello@gmail.com', username: 'John', persisted: true
        )
      end

      context 'when block is given to registration controller' do
        let(:canary) { proc { |_resource| } }
        let(:block) { proc { |resource| canary.call(resource) } }

        context 'when tracking mode set to safe' do
          before { settings.appsec.track_user_events.mode = 'safe' }

          it 'tracks signup event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup)
              .with(
                active_context.trace,
                active_context.span,
                user_id: nil,
                **{}
              )
            expect(canary).to receive(:call).with(resource)

            expect(controller.create(&block)).to eq(true)
          end
        end

        context 'when tracking mode set to extended' do
          before { settings.appsec.track_user_events.mode = 'extended' }

          it 'tracks signup event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup)
              .with(
                active_context.trace,
                active_context.span,
                user_id: nil,
                **{ email: 'hello@gmail.com', username: 'John' }
              )
            expect(canary).to receive(:call).with(resource)

            expect(controller.create(&block)).to eq(true)
          end
        end
      end

      context 'when no block is given to registration controller' do
        context 'when tracking mode set to safe' do
          before { settings.appsec.track_user_events.mode = 'safe' }

          it 'tracks signup event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup)
              .with(
                active_context.trace,
                active_context.span,
                user_id: nil,
                **{}
              )

            expect(controller.create).to eq(true)
          end
        end

        context 'when tracking mode set to extended' do
          before { settings.appsec.track_user_events.mode = 'extended' }

          it 'tracks signup event' do
            expect(Datadog::AppSec::Contrib::Devise::Tracking).to receive(:track_signup)
              .with(
                active_context.trace,
                active_context.span,
                user_id: nil,
                **{ email: 'hello@gmail.com', username: 'John' }
              )

            expect(controller.create).to eq(true)
          end
        end
      end
    end
  end

  context 'when registration defines current user as non-persisted resource' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(active_context)

      settings.appsec.track_user_events.enabled = true
      settings.appsec.track_user_events.mode = 'safe'
    end

    let(:active_context) { instance_double(Datadog::AppSec::Context, trace: double, span: double) }
    let(:controller) { mock_controller.new(true, resource) }
    let(:resource) do
      Datadog::AppSec::Contrib::Support::DeviseUserMock.new(
        id: nil, email: nil, username: nil, persisted: false
      )
    end

    context 'when block is not given to registration controller' do
      context 'when tracking mode set to safe' do
        before { settings.appsec.track_user_events.mode = 'safe' }

        it 'does not track signup event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)

          expect(controller.create).to eq(true)
        end
      end

      context 'when tracking mode set to extended' do
        before { settings.appsec.track_user_events.mode = 'extended' }

        it 'does not track signup event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)

          expect(controller.create).to eq(true)
        end
      end
    end

    context 'when block is given to registration controller' do
      let(:canary) { proc { |_resource| } }
      let(:block) { proc { |resource| canary.call(resource) } }

      context 'when tracking mode set to safe' do
        before { settings.appsec.track_user_events.mode = 'safe' }

        it 'does not track signup event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
          expect(canary).to receive(:call).with(resource)

          expect(controller.create(&block)).to eq(true)
        end
      end

      context 'when tracking mode set to extended' do
        before { settings.appsec.track_user_events.mode = 'extended' }

        it 'does not track signup event' do
          expect(Datadog::AppSec::Contrib::Devise::Tracking).to_not receive(:track_signup)
          expect(canary).to receive(:call).with(resource)

          expect(controller.create(&block)).to eq(true)
        end
      end
    end
  end
end
