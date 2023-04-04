# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/configuration/path'

RSpec.describe Datadog::Core::Remote::Configuration::Path do
  describe '.parse' do
    context 'invalid path' do
      it 'raises ParseError' do
        expect { described_class.parse('invalid_path') }.to raise_error(described_class::ParseError)
      end
    end

    context 'valid path' do
      it 'returns a Path instance' do
        path = described_class.parse('datadog/123/ASM/blocked_ips/config')
        expect(path).to be_a(described_class)
        expect(path.source).to eq('datadog')
        expect(path.org_id).to eq(123)
        expect(path.product).to eq('ASM')
        expect(path.config_id).to eq('blocked_ips')
        expect(path.name).to eq('config')
      end

      it 'returns an emplyee Path instance without org_id' do
        path = described_class.parse('employee/ASM/blocked_ips/config')
        expect(path).to be_a(described_class)
        expect(path.source).to eq('employee')
        expect(path.org_id).to be_nil
        expect(path.product).to eq('ASM')
        expect(path.config_id).to eq('blocked_ips')
        expect(path.name).to eq('config')
      end
    end
  end

  describe '#==' do
    it 'returns if two path are the same' do
      path1 = described_class.parse('datadog/123/ASM/blocked_ips/config')
      path1dup = path1.dup
      path2 = described_class.parse('employee/ASM/blocked_ips/config')

      expect(path1 == path1dup).to be_truthy
      expect(path1 == path2).to be_falsy
    end
  end

  describe '#eql?' do
    it 'returns if two path are the same' do
      path1 = described_class.parse('datadog/123/ASM/blocked_ips/config')
      path2 = described_class.parse('employee/ASM/blocked_ips/config')

      expect(path1).to be_eql(path1)
      expect(path1).not_to be_eql(path2)
    end
  end
end
