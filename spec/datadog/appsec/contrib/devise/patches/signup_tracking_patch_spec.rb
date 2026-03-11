# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/devise/patches/signup_tracking_patch'

RSpec.describe Datadog::AppSec::Contrib::Devise::Patches::SignupTrackingPatch do
  before { allow(Datadog).to receive(:configuration).and_return(settings) }

  let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:context) { instance_double(Datadog::AppSec::Context, trace: trace) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:devise_controller) do
    Class.new do
      prepend Datadog::AppSec::Contrib::Devise::Patches::SignupTrackingPatch

      def create
        'no-op'
      end
    end
  end

  context 'when AppSec is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(false)
      settings.appsec.auto_user_instrumentation.mode = 'identification'
    end

    it 'does not track signup event' do
      expect(trace).not_to receive(:keep!)

      devise_controller.new.create
    end
  end

  context 'when automated user tracking is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      settings.appsec.auto_user_instrumentation.mode = 'identification'
    end

    it 'does not track signup event' do
      expect(trace).not_to receive(:keep!)

      devise_controller.new.create
    end
  end

  context 'when AppSec active context is not set' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(nil)

      settings.appsec.auto_user_instrumentation.mode = 'identification'
    end

    it 'does not track signup event' do
      expect(trace).not_to receive(:keep!)

      devise_controller.new.create
    end
  end

  context 'has_explicit_login in user lifecycle events' do
    let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:gateway) { instance_double(Datadog::AppSec::Instrumentation::Gateway) }
    let(:extractor) { instance_double(Datadog::AppSec::Contrib::Devise::DataExtractor) }
    let(:resource) { double('ActiveRecord::BaseModel', new_record?: false, active_for_authentication?: true) }

    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(context)
      allow(context).to receive(:span).and_return(span)
      allow(span).to receive(:[]=)
      allow(span).to receive(:[]).and_return(nil)
      allow(Datadog::AppSec::TraceKeeper).to receive(:keep!)
      allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
      allow(gateway).to receive(:push)
      allow(Datadog::AppSec::Contrib::Devise::DataExtractor).to receive(:new).and_return(extractor)

      settings.appsec.auto_user_instrumentation.mode = 'identification'
    end

    let(:controller) do
      Class.new do
        prepend Datadog::AppSec::Contrib::Devise::Patches::SignupTrackingPatch

        attr_accessor :resource_for_yield

        def create
          yield(resource_for_yield) if block_given?
        end

        def resource_params
          {}
        end
      end
    end

    context 'when login differs from id' do
      before do
        allow(extractor).to receive(:extract_id).and_return('42')
        allow(extractor).to receive(:extract_login).and_return('john@example.com')
      end

      it 'sets has_user_login to true' do
        instance = controller.new
        instance.resource_for_yield = resource
        instance.create

        expect(gateway).to have_received(:push).with(
          'appsec.events.user_lifecycle',
          an_object_having_attributes(
            event: 'users.signup',
            has_user_id: true,
            has_user_login: true,
          )
        )
      end
    end

    context 'when login equals id' do
      before do
        allow(extractor).to receive(:extract_id).and_return('42')
        allow(extractor).to receive(:extract_login).and_return('42')
      end

      it 'sets has_user_login to false' do
        instance = controller.new
        instance.resource_for_yield = resource
        instance.create

        expect(gateway).to have_received(:push).with(
          'appsec.events.user_lifecycle',
          an_object_having_attributes(
            event: 'users.signup',
            has_user_id: true,
            has_user_login: false,
          )
        )
      end
    end

    context 'when login is nil' do
      before do
        allow(extractor).to receive(:extract_id).and_return('42')
        allow(extractor).to receive(:extract_login).and_return(nil)
      end

      it 'sets has_user_login to false' do
        instance = controller.new
        instance.resource_for_yield = resource
        instance.create

        expect(gateway).to have_received(:push).with(
          'appsec.events.user_lifecycle',
          an_object_having_attributes(
            event: 'users.signup',
            has_user_id: true,
            has_user_login: false,
          )
        )
      end
    end
  end
end
