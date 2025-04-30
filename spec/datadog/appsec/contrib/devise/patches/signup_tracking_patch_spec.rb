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
end
