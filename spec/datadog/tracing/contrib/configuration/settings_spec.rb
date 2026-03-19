require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::Configuration::Settings do
  subject(:settings) { described_class.new }

  it { is_expected.to be_a_kind_of(Datadog::Core::Configuration::Base) }

  describe '#service_name' do
    subject(:service_name) { settings.service_name }

    it { expect(settings.service_name).to be nil }
    it { expect(settings[:service_name]).to be nil }
  end

  describe '#analytics_enabled' do
    subject(:analytics_enabled) { settings.analytics_enabled }

    it { expect(settings.analytics_enabled).to be false }
    it { expect(settings[:analytics_enabled]).to be false }
  end

  describe '#analytics_sample_rate' do
    subject(:analytics_sample_rate) { settings.analytics_sample_rate }

    it { expect(settings.analytics_sample_rate).to eq 1.0 }
    it { expect(settings[:analytics_sample_rate]).to eq 1.0 }
  end

  describe '#configure' do
    subject(:configure) { settings.configure(options) }

    context 'given an option' do
      let(:options) { {service_name: service_name} }
      let(:service_name) { 'service_name' }

      before { allow(settings).to receive(:set_option).and_call_original }

      it 'doesn\'t initialize other options' do
        expect { configure }
          .to change { settings.service_name }
          .from(nil)
          .to(service_name)

        expect(settings).to_not have_received(:set_option).with(:tracer, any_args)
      end
    end
  end

  describe '.configure_settings_path!' do
    subject(:settings_class) do
      Class.new(described_class) do
        option :custom_option, default: false

        settings :nested do
          option :enabled, default: true
        end
      end
    end

    before do
      settings_class.configure_settings_path!('tracing.fake_integration')
    end

    it 'computes inherited option names from the settings path' do
      settings = settings_class.new

      expect(settings.send(:resolve_option, :analytics_enabled).name).to eq('tracing.fake_integration.analytics_enabled')
      expect(settings.send(:resolve_option, :custom_option).name).to eq('tracing.fake_integration.custom_option')
    end

    it 'computes nested option names from the settings path' do
      expect(settings_class.new.nested.send(:resolve_option, :enabled).name).to eq('tracing.fake_integration.nested.enabled')
    end
  end
end
