# frozen_string_literal: true

require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::Contrib::Devise::Configuration do
  let(:settings) { Datadog::Core::Configuration::Settings.new }

  before do
    allow(Datadog).to receive(:configuration).and_return(settings)
    allow(Datadog).to receive(:logger).and_return(instance_double(Datadog::Core::Logger).as_null_object)
  end

  describe '.auto_user_instrumentation_enabled?' do
    context 'when auto_user_instrumentation is explicitly disabled and track_user_events is default' do
      before { settings.appsec.auto_user_instrumentation.mode = 'disabled' }

      it { expect(described_class).not_to be_auto_user_instrumentation_enabled }
    end

    context 'when auto_user_instrumentation is invalid and track_user_events is default' do
      before { settings.appsec.auto_user_instrumentation.mode = 'invalid' }

      it { expect(described_class).not_to be_auto_user_instrumentation_enabled }
    end

    context 'when track_user_events is explicitly set and auto_user_instrumentation is default' do
      before { settings.appsec.track_user_events.enabled = false }

      it { expect(described_class).not_to be_auto_user_instrumentation_enabled }
    end

    context 'when auto_user_instrumentation is enabled and track_user_events is enabled' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'identification'
        settings.appsec.track_user_events.enabled = true
      end

      it { expect(described_class).to be_auto_user_instrumentation_enabled }
    end

    context 'when auto_user_instrumentation is enabled, but track_user_events is disabled' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'identification'
        settings.appsec.track_user_events.enabled = false
      end

      it { expect(described_class).to be_auto_user_instrumentation_enabled }
    end

    context 'when auto_user_instrumentation is disabled, but track_user_events is enabled' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'disabled'
        settings.appsec.track_user_events.enabled = true
      end

      it { expect(described_class).not_to be_auto_user_instrumentation_enabled }
    end

    context 'when auto_user_instrumentation is disabled and track_user_events is disabled' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'disabled'
        settings.appsec.track_user_events.enabled = false
      end

      it { expect(described_class).not_to be_auto_user_instrumentation_enabled }
    end
  end

  describe '.auto_user_instrumentation_mode' do
    context 'when auto_user_instrumentation is explicitly set and track_user_events is default' do
      before { settings.appsec.auto_user_instrumentation.mode = 'identification' }

      it { expect(described_class.auto_user_instrumentation_mode).to eq('identification') }
    end

    context 'when track_user_events is explicitly set and auto_user_instrumentation is default' do
      before { settings.appsec.track_user_events.mode = 'safe' }

      it { expect(described_class.auto_user_instrumentation_mode).to eq('anonymization') }
    end

    context 'when auto_user_instrumentation is ident and track_user_events is extended' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'identification'
        settings.appsec.track_user_events.mode = 'extended'
      end

      it { expect(described_class.auto_user_instrumentation_mode).to eq('identification') }
    end

    context 'when auto_user_instrumentation is ident and track_user_events is safe' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'identification'
        settings.appsec.track_user_events.mode = 'safe'
      end

      it { expect(described_class.auto_user_instrumentation_mode).to eq('identification') }
    end

    context 'when auto_user_instrumentation is anon and track_user_events is extended' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'anonymization'
        settings.appsec.track_user_events.mode = 'extended'
      end

      it { expect(described_class.auto_user_instrumentation_mode).to eq('anonymization') }
    end

    context 'when auto_user_instrumentation is anon and track_user_events is safe' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'anonymization'
        settings.appsec.track_user_events.mode = 'safe'
      end

      it { expect(described_class.auto_user_instrumentation_mode).to eq('anonymization') }
    end

    context 'when auto_user_instrumentation is ident and track_user_events is invalid' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'anonymization'
        settings.appsec.track_user_events.mode = 'invalid'
      end

      it { expect(described_class.auto_user_instrumentation_mode).to eq('anonymization') }
    end

    context 'when auto_user_instrumentation is invalid and track_user_events is safe' do
      before do
        settings.appsec.auto_user_instrumentation.mode = 'invalid'
        settings.appsec.track_user_events.mode = 'safe'
      end

      it { expect(described_class.auto_user_instrumentation_mode).to eq('disabled') }
    end
  end
end
