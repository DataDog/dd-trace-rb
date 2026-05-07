# frozen_string_literal: true

require 'datadog/tracing/component'
require 'datadog/tracing/transport/native'

RSpec.describe 'Native transport configuration' do
  before do
    skip_if_libdatadog_not_supported
  end

  describe 'Datadog::Tracing::Component.build_writer' do
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        s.tracing.native_transport = native_transport_enabled
      end
    end
    let(:agent_settings) do
      double('agent_settings', url: 'http://127.0.0.1:8126')
    end
    let(:logger) { Logger.new('/dev/null') }

    before { allow(Datadog).to receive(:logger).and_return(logger) }

    context 'when native_transport is false (default)' do
      let(:native_transport_enabled) { false }

      it 'builds a writer with the default HTTP transport' do
        writer = Datadog::Tracing::Component.send(:build_writer, settings, agent_settings)
        expect(writer).to be_a(Datadog::Tracing::Writer)
        # The transport should NOT be our native one
        transport = writer.instance_variable_get(:@transport)
        expect(transport).not_to be_a(Datadog::Tracing::Transport::Native::Transport)
      end
    end

    context 'when native_transport is true' do
      let(:native_transport_enabled) { true }

      it 'builds a writer with the native transport' do
        writer = Datadog::Tracing::Component.send(:build_writer, settings, agent_settings)
        expect(writer).to be_a(Datadog::Tracing::Writer)
        transport = writer.instance_variable_get(:@transport)
        expect(transport).to be_a(Datadog::Tracing::Transport::Native::Transport)
      end
    end

    context 'when native_transport is true but native extension is unavailable' do
      let(:native_transport_enabled) { true }

      before do
        allow(Datadog::Tracing::Transport::Native).to receive(:supported?).and_return(false)
        stub_const('Datadog::Tracing::Transport::Native::UNSUPPORTED_REASON', 'test: not available')
      end

      it 'falls back to the default HTTP transport with a warning' do
        expect(logger).to receive(:warn).with(/not available/)
        writer = Datadog::Tracing::Component.send(:build_writer, settings, agent_settings)
        transport = writer.instance_variable_get(:@transport)
        expect(transport).not_to be_a(Datadog::Tracing::Transport::Native::Transport)
      end
    end
  end

  describe 'settings' do
    it 'has native_transport defaulting to false' do
      settings = Datadog::Core::Configuration::Settings.new
      expect(settings.tracing.native_transport).to be false
    end

    it 'can be set to true' do
      settings = Datadog::Core::Configuration::Settings.new
      settings.tracing.native_transport = true
      expect(settings.tracing.native_transport).to be true
    end
  end
end
