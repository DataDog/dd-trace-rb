require 'spec_helper'
require 'datadog/core/environment/socket'

RSpec.describe Datadog::Core::Environment::Socket do
  describe '::hostname' do
    subject(:hostname) { described_class.hostname }

    it { is_expected.to be_a_kind_of(String) }
  end

  describe '::resolved_hostname' do
    subject(:resolved) { described_class.resolved_hostname(settings) }

    let(:tracing) { double('tracing', report_hostname: true) }
    let(:settings) { double('settings', hostname: configured_hostname, tracing: tracing) }

    context 'when report_hostname is disabled' do
      let(:configured_hostname) { 'custom-host' }
      let(:tracing) { double('tracing', report_hostname: false) }

      it { expect(resolved).to be_nil }
    end

    context 'when hostname was set via settings' do
      let(:configured_hostname) { 'custom-host' }

      it 'returns the configured hostname' do
        expect(resolved).to eq('custom-host')
      end
    end

    context 'when DD_HOSTNAME is empty' do
      let(:configured_hostname) { '' }

      it 'falls back to the system hostname' do
        expect(resolved).to eq(described_class.hostname)
      end
    end

    context 'when DD_HOSTNAME is not set' do
      let(:configured_hostname) { nil }

      it 'returns the system hostname' do
        expect(resolved).to eq(described_class.hostname)
      end
    end

    context 'when both configured and system hostname are empty' do
      let(:configured_hostname) { '' }

      before { allow(described_class).to receive(:hostname).and_return('') }

      it 'returns nil' do
        expect(resolved).to be_nil
      end
    end
  end
end
