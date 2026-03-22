# frozen_string_literal: true

require 'datadog/symbol_database/component'

RSpec.describe Datadog::SymbolDatabase::Component do
  let(:logger) { double('logger', debug: nil).tap { |l| allow(l).to receive(:debug).and_yield } }

  describe '.build' do
    context 'when symbol_database is enabled and remote is available' do
      let(:settings) do
        s = double('settings')
        sd = double('symbol_database', enabled: true, force_upload: false, includes: [])
        r = double('remote', enabled: true)
        allow(s).to receive(:respond_to?).with(:symbol_database).and_return(true)
        allow(s).to receive(:respond_to?).with(:remote).and_return(true)
        allow(s).to receive(:symbol_database).and_return(sd)
        allow(s).to receive(:remote).and_return(r)
        allow(s).to receive(:service).and_return('test')
        allow(s).to receive(:env).and_return('dev')
        allow(s).to receive(:version).and_return('1.0')
        s
      end
      let(:agent_settings) { double('agent_settings', hostname: 'localhost', port: 8126) }

      it 'returns a Component instance' do
        component = described_class.build(settings, agent_settings, logger)
        expect(component).to be_a(described_class)
        component.shutdown!
      end
    end

    context 'when symbol_database is disabled' do
      let(:settings) do
        s = double('settings')
        sd = double('symbol_database', enabled: false)
        allow(s).to receive(:respond_to?).with(:symbol_database).and_return(true)
        allow(s).to receive(:symbol_database).and_return(sd)
        s
      end
      let(:agent_settings) { double('agent_settings') }

      it 'returns nil' do
        expect(described_class.build(settings, agent_settings, logger)).to be_nil
      end
    end

    context 'when remote is not available and force_upload is false' do
      let(:settings) do
        s = double('settings')
        sd = double('symbol_database', enabled: true, force_upload: false)
        allow(s).to receive(:respond_to?).with(:symbol_database).and_return(true)
        allow(s).to receive(:respond_to?).with(:remote).and_return(false)
        allow(s).to receive(:symbol_database).and_return(sd)
        s
      end
      let(:agent_settings) { double('agent_settings') }

      it 'returns nil' do
        expect(described_class.build(settings, agent_settings, logger)).to be_nil
      end
    end
  end

  describe '#start_upload' do
    let(:settings) do
      s = double('settings')
      sd = double('symbol_database', enabled: true, force_upload: false, includes: [])
      r = double('remote', enabled: true)
      allow(s).to receive(:respond_to?).with(:symbol_database).and_return(true)
      allow(s).to receive(:respond_to?).with(:remote).and_return(true)
      allow(s).to receive(:symbol_database).and_return(sd)
      allow(s).to receive(:remote).and_return(r)
      allow(s).to receive(:service).and_return('test')
      allow(s).to receive(:env).and_return('dev')
      allow(s).to receive(:version).and_return('1.0')
      s
    end
    let(:agent_settings) { double('agent_settings', hostname: 'localhost', port: 8126) }
    let(:component) { described_class.build(settings, agent_settings, logger) }

    after { component&.shutdown! }

    it 'does not raise on extraction' do
      # Upload will fail (no agent), but should not raise
      expect { component.start_upload }.not_to raise_error
    end

    it 'skips upload if called again within dedup window' do
      component.start_upload
      # Second call should be skipped
      expect(logger).to receive(:debug).and_yield
      component.start_upload
    end
  end
end
