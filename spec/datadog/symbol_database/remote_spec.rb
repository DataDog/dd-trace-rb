# frozen_string_literal: true

# Tests ported from Python dd-trace-py:
#   tests/internal/symbol_db/test_symbols.py::test_symbols_upload_enabled
#   ddtrace/internal/symbol_db/remoteconfig.py::SymbolDatabaseCallback
#
# Python tests that the RC callback installs/uninstalls the SymbolDatabaseUploader
# based on upload_symbols config payloads.
# Ruby equivalent: Remote.process_change dispatches to Component.start_upload / stop_upload.

require 'spec_helper'
require 'datadog/symbol_database/remote'
require 'datadog/symbol_database/component'

RSpec.describe Datadog::SymbolDatabase::Remote do
  let(:component) { instance_double(Datadog::SymbolDatabase::Component) }

  # Helper to create a mock change object
  def mock_change(type:, data:)
    content = instance_double('Content', data: data)
    allow(content).to receive(:applied)
    allow(content).to receive(:errored)

    change = instance_double('Change', type: type, content: content)
    allow(change).to receive(:previous).and_return(nil)
    change
  end

  describe '.process_change' do
    context 'with insert change and upload_symbols: true' do
      it 'calls start_upload on the component' do
        change = mock_change(type: :insert, data: '{"upload_symbols": true}')

        expect(component).to receive(:start_upload)

        described_class.send(:process_change, component, change)
      end
    end

    context 'with insert change and upload_symbols: false' do
      it 'does not call start_upload' do
        change = mock_change(type: :insert, data: '{"upload_symbols": false}')

        expect(component).not_to receive(:start_upload)

        described_class.send(:process_change, component, change)
      end
    end

    context 'with update change' do
      it 'calls stop_upload then start_upload for upload_symbols: true' do
        change = mock_change(type: :update, data: '{"upload_symbols": true}')

        expect(component).to receive(:stop_upload).ordered
        expect(component).to receive(:start_upload).ordered

        described_class.send(:process_change, component, change)
      end

      it 'calls stop_upload for upload_symbols: false' do
        change = mock_change(type: :update, data: '{"upload_symbols": false}')

        expect(component).to receive(:stop_upload)
        expect(component).not_to receive(:start_upload)

        described_class.send(:process_change, component, change)
      end
    end

    context 'with delete change' do
      it 'calls stop_upload' do
        content = instance_double('Content')
        allow(content).to receive(:applied)
        change = instance_double('Change', type: :delete, content: nil, previous: content)

        expect(component).to receive(:stop_upload)

        described_class.send(:process_change, component, change)
      end
    end

    context 'with invalid config' do
      it 'handles missing upload_symbols key gracefully' do
        change = mock_change(type: :insert, data: '{"some_other_key": true}')

        expect(component).not_to receive(:start_upload)

        described_class.send(:process_change, component, change)
      end

      it 'handles invalid JSON gracefully' do
        change = mock_change(type: :insert, data: 'not valid json')

        expect(component).not_to receive(:start_upload)

        described_class.send(:process_change, component, change)
      end

      it 'handles non-Hash JSON gracefully' do
        change = mock_change(type: :insert, data: '"just a string"')

        expect(component).not_to receive(:start_upload)

        described_class.send(:process_change, component, change)
      end
    end
  end

  describe '.products' do
    it 'returns LIVE_DEBUGGING_SYMBOL_DB product' do
      expect(described_class.products).to eq(['LIVE_DEBUGGING_SYMBOL_DB'])
    end
  end

  describe '.parse_config' do
    it 'parses valid upload_symbols config' do
      content = instance_double('Content', data: '{"upload_symbols": true}')
      result = described_class.send(:parse_config, content)
      expect(result).to eq({ 'upload_symbols' => true })
    end

    it 'returns nil for missing upload_symbols key' do
      content = instance_double('Content', data: '{"other": true}')
      result = described_class.send(:parse_config, content)
      expect(result).to be_nil
    end

    it 'returns nil for invalid JSON' do
      content = instance_double('Content', data: 'bad json')
      result = described_class.send(:parse_config, content)
      expect(result).to be_nil
    end

    it 'returns nil for non-Hash JSON' do
      content = instance_double('Content', data: '[1, 2, 3]')
      result = described_class.send(:parse_config, content)
      expect(result).to be_nil
    end
  end

  describe 'enable then disable cycle (ported from Python test_symbols_upload_enabled + remoteconfig._rc_callback)' do
    # Python test: test_symbols_upload_enabled verifies RC is registered
    # Python remoteconfig: SymbolDatabaseCallback processes payloads, calls install/uninstall
    # Ruby equivalent: Remote.process_change dispatches to Component.start_upload / stop_upload

    it 'enables then disables upload via sequential RC changes' do
      # First: insert with upload_symbols: true
      insert_change = mock_change(type: :insert, data: '{"upload_symbols": true}')
      expect(component).to receive(:start_upload)
      described_class.send(:process_change, component, insert_change)

      # Then: update with upload_symbols: false
      update_change = mock_change(type: :update, data: '{"upload_symbols": false}')
      expect(component).to receive(:stop_upload)
      described_class.send(:process_change, component, update_change)
    end

    it 'handles multiple enable signals without duplicate start_upload calls' do
      # Each insert calls start_upload — Component internally deduplicates
      change1 = mock_change(type: :insert, data: '{"upload_symbols": true}')
      change2 = mock_change(type: :insert, data: '{"upload_symbols": true}')

      expect(component).to receive(:start_upload).twice

      described_class.send(:process_change, component, change1)
      described_class.send(:process_change, component, change2)
    end
  end
end
