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
end
