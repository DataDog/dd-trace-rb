# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/devise/patches/signin_tracking_patch'

RSpec.describe Datadog::AppSec::Contrib::Devise::Patches::SigninTrackingPatch do
  before { allow(Datadog).to receive(:configuration).and_return(settings) }

  let(:user) { double('ActiveRecord::BaseModel') }
  let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:context) { instance_double(Datadog::AppSec::Context, trace: trace) }
  let(:devise_strategy) do
    Class.new do
      prepend Datadog::AppSec::Contrib::Devise::Patches::SigninTrackingPatch

      def validate(resource, &block)
        true
      end
    end
  end

  context 'when AppSec is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(false)
      settings.appsec.auto_user_instrumentation.mode = 'disabled'
    end

    it 'does not track successful signin event' do
      expect(trace).not_to receive(:keep!)

      devise_strategy.new.validate(user)
    end
  end

  context 'when automated user tracking is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      settings.appsec.auto_user_instrumentation.mode = 'disabled'
    end

    it 'does not track successful signin event' do
      expect(trace).not_to receive(:keep!)

      devise_strategy.new.validate(user)
    end
  end

  context 'when AppSec active context is not set' do
    before do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(nil)

      settings.appsec.auto_user_instrumentation.mode = 'identification'
    end

    it 'does not track successful signin event' do
      expect(trace).not_to receive(:keep!)

      devise_strategy.new.validate(user)
    end
  end

  context 'has_explicit_login in user lifecycle events' do
    let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:gateway) { instance_double(Datadog::AppSec::Instrumentation::Gateway) }
    let(:extractor) { instance_double(Datadog::AppSec::Contrib::Devise::DataExtractor) }

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

    let(:strategy) do
      Class.new do
        prepend Datadog::AppSec::Contrib::Devise::Patches::SigninTrackingPatch

        attr_accessor :validate_result

        def validate(resource, &block)
          validate_result
        end

        def authentication_hash
          {}
        end
      end
    end

    context 'when login differs from id on successful signin' do
      before do
        allow(extractor).to receive(:extract_id).and_return('42')
        allow(extractor).to receive(:extract_login).and_return('john@example.com')
      end

      it 'sets has_user_login to true' do
        instance = strategy.new
        instance.validate_result = true
        instance.validate(user)

        expect(gateway).to have_received(:push).with(
          'appsec.events.user_lifecycle',
          an_object_having_attributes(
            event: 'users.login.success',
            has_user_id: true,
            has_user_login: true,
          )
        )
      end
    end

    context 'when login equals id on successful signin' do
      before do
        allow(extractor).to receive(:extract_id).and_return('42')
        allow(extractor).to receive(:extract_login).and_return('42')
      end

      it 'sets has_user_login to false' do
        instance = strategy.new
        instance.validate_result = true
        instance.validate(user)

        expect(gateway).to have_received(:push).with(
          'appsec.events.user_lifecycle',
          an_object_having_attributes(
            event: 'users.login.success',
            has_user_id: true,
            has_user_login: false,
          )
        )
      end
    end

    context 'when login is nil on successful signin' do
      before do
        allow(extractor).to receive(:extract_id).and_return('42')
        allow(extractor).to receive(:extract_login).and_return(nil)
      end

      it 'sets has_user_login to false' do
        instance = strategy.new
        instance.validate_result = true
        instance.validate(user)

        expect(gateway).to have_received(:push).with(
          'appsec.events.user_lifecycle',
          an_object_having_attributes(
            event: 'users.login.success',
            has_user_id: true,
            has_user_login: false,
          )
        )
      end
    end

    context 'when login equals id on failed signin with resource' do
      before do
        allow(extractor).to receive(:extract_id).and_return('42')
        allow(extractor).to receive(:extract_login).and_return('42')
      end

      it 'sets has_user_login to false' do
        instance = strategy.new
        instance.validate_result = false
        instance.validate(user)

        expect(gateway).to have_received(:push).with(
          'appsec.events.user_lifecycle',
          an_object_having_attributes(
            event: 'users.login.failure',
            has_user_id: true,
            has_user_login: false,
          )
        )
      end
    end

    context 'when login differs from id on failed signin with resource' do
      before do
        allow(extractor).to receive(:extract_id).and_return('42')
        allow(extractor).to receive(:extract_login).and_return('john@example.com')
      end

      it 'sets has_user_login to true' do
        instance = strategy.new
        instance.validate_result = false
        instance.validate(user)

        expect(gateway).to have_received(:push).with(
          'appsec.events.user_lifecycle',
          an_object_having_attributes(
            event: 'users.login.failure',
            has_user_id: true,
            has_user_login: true,
          )
        )
      end
    end
  end
end
