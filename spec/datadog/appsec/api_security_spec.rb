# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/api_security'

RSpec.describe Datadog::AppSec::APISecurity do
  describe '.enabled?' do
    context 'when API security is disabled' do
      around do |example|
        Datadog.configure { |c| c.appsec.api_security.enabled = false }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.enabled?).to be(false) }
    end

    context 'when API security is enabled' do
      around do |example|
        Datadog.configure { |c| c.appsec.api_security.enabled = true }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.enabled?).to be(true) }
    end
  end

  describe '.sample?' do
    before { allow(Datadog::AppSec::APISecurity::Sampler).to receive(:thread_local).and_return(sampler) }

    let(:sampler) { spy(Datadog::AppSec::APISecurity::Sampler) }
    let(:request) { double('Rack::Request') }
    let(:response) { double('Rack::Response') }

    it 'delegates sampling to the api security sampler' do
      described_class.sample?(request, response)

      expect(sampler).to have_received(:sample?).with(request, response)
    end
  end

  describe '.sample_trace?' do
    let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }

    context 'when running in standalone mode' do
      around do |example|
        Datadog.configure { |c| c.apm.tracing.enabled = false }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.sample_trace?(trace)).to be(true) }
    end

    context 'when running in normal mode' do
      around do |example|
        Datadog.configure do |c|
          c.apm.tracing.enabled = true
          c.tracing.sampler = sampler
        end

        example.run
      ensure
        Datadog.configuration.reset!
      end

      let(:sampler) { instance_double(Datadog::Tracing::Sampling::PrioritySampler) }

      context 'when sampler allows trace' do
        before { allow(sampler).to receive(:sample!).with(trace).and_return(true) }

        it { expect(described_class.sample_trace?(trace)).to be(true) }
      end

      context 'when sampler rejects trace' do
        before { allow(sampler).to receive(:sample!).with(trace).and_return(false) }

        it { expect(described_class.sample_trace?(trace)).to be(false) }
      end
    end
  end
end
