# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/rack/integration'

RSpec.describe Datadog::Tracing::Contrib::Rack::MiddlewarePatcher do
  describe '#patch' do
    before do
      Datadog.configure do |c|
        c.tracing.instrument :rack, use_events: use_events
      end

      described_class.instance_variable_set(:@patch_only_once, nil)
    end

    after do
      Datadog.registry[:rack].reset_configuration!
      described_class.instance_variable_set(:@patch_only_once, nil)
    end

    context 'when use_events is false (default)' do
      let(:use_events) { false }

      it 'does not emit a warning' do
        expect(Datadog.logger).not_to receive(:warn)
        described_class.patch
      end

      it 'loads TraceMiddleware' do
        described_class.patch
        expect(defined?(Datadog::Tracing::Contrib::Rack::TraceMiddleware)).to be_truthy
      end
    end

    context 'when use_events is true and Rack >= 2.0' do
      let(:use_events) { true }

      before do
        allow(Datadog::Tracing::Contrib::Rack::Integration).to receive(:version)
          .and_return(Gem::Version.new('2.3.0'))
      end

      it 'does not emit a warning' do
        expect(Datadog.logger).not_to receive(:warn)
        described_class.patch
      end

      it 'loads EventHandler' do
        described_class.patch
        expect(defined?(Datadog::Tracing::Contrib::Rack::EventHandler)).to be_truthy
      end
    end

    context 'when use_events is true and Rack < 2.0' do
      let(:use_events) { true }

      before do
        allow(Datadog::Tracing::Contrib::Rack::Integration).to receive(:version)
          .and_return(Gem::Version.new('1.6.0'))
      end

      it 'emits a warning about the version requirement' do
        expect(Datadog.logger).to receive(:warn).with(/use_events requires Rack >= 2\.0\.0/)
        described_class.patch
      end

      it 'loads TraceMiddleware as fallback' do
        allow(Datadog.logger).to receive(:warn)
        described_class.patch
        expect(defined?(Datadog::Tracing::Contrib::Rack::TraceMiddleware)).to be_truthy
      end
    end
  end
end
