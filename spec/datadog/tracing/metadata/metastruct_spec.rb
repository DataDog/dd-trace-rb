require 'datadog/tracing/metadata/metastruct'

RSpec.describe Datadog::Tracing::Metadata::Metastruct do
  subject(:metastruct) { test_object.send(:metastruct) }
  let(:test_object) { described_class.new(preexisting_metastruct) }
  let(:preexisting_metastruct) { nil }

  describe '#initialize' do
    context 'when setting meta struct' do
      context 'with empty metastruct' do
        it { is_expected.to eq({}) }
      end

      context 'with not empty metastruct' do
        let(:preexisting_metastruct) { { 'key' => 'value' } }

        it { is_expected.to eq({ 'key' => 'value' }) }
      end
    end
  end

  describe '#deep_merge!' do
    context 'when merging meta struct' do
      before do
        test_object.deep_merge!(new_metastruct)
      end

      let(:preexisting_metastruct) { nil }

      context 'with empty preexisting metastruct' do
        let(:new_metastruct) { { 'key' => 'value' } }

        it { is_expected.to eq({ 'key' => 'value' }) }
      end

      context 'with simple preexisting metastruct' do
        let(:preexisting_metastruct) { { 'old_key' => 'old_value' } }

        context 'with new key' do
          let(:new_metastruct) { { 'new_key' => 'new_value' } }

          it { is_expected.to eq({ 'old_key' => 'old_value', 'new_key' => 'new_value' }) }
        end

        context 'with existing key' do
          let(:new_metastruct) { { 'old_key' => 'new_value' } }

          it { is_expected.to eq({ 'old_key' => 'new_value' }) }
        end
      end

      context 'with nested preexisting metastruct, containing arrays' do
        let(:preexisting_metastruct) { { 'key' => { 'nested_key' => ['value1'] } } }
        let(:new_metastruct) { { 'key' => { 'nested_key' => ['value2'], 'second_nested_key' => ['value3'] } } }

        it { is_expected.to eq({ 'key' => { 'nested_key' => ['value1', 'value2'], 'second_nested_key' => ['value3'] } }) }
      end
    end
  end
end
