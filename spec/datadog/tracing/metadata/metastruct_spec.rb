require 'datadog/tracing/metadata/metastruct'

RSpec.describe Datadog::Tracing::Metadata::Metastruct do
  subject(:test_object) { test_class.new }
  let(:test_class) { Class.new { include Datadog::Tracing::Metadata::Metastruct } }

  describe '#metastruct=' do
    subject(:metastruct_instance_var) { test_object.send(:metastruct) }

    context 'when setting meta struct' do
      before do
        test_object.instance_variable_set(:@metastruct, preexisting_metastruct)
        test_object.metastruct = new_metastruct
      end

      let(:preexisting_metastruct) { nil }

      context 'with empty preexisting metastruct' do
        let(:new_metastruct) { { 'key' => 'value' } }

        it { is_expected.to eq({ 'key' => 'value' }) }
      end

      context 'with preexisting metastruct' do
        let(:preexisting_metastruct) { { 'old_key' => 'old_value' } }

        context 'with new key' do
          let(:new_metastruct) { { 'new_key' => 'new_value' } }

          it { is_expected.to eq({ 'new_key' => 'new_value' }) }
        end

        context 'with existing key' do
          let(:new_metastruct) { { 'old_key' => 'new_value' } }

          it { is_expected.to eq({ 'old_key' => 'new_value' }) }
        end
      end
    end
  end

  describe '#deep_merge_metastruct!' do
    subject(:metastruct_instance_var) { test_object.send(:metastruct) }

    context 'when merging meta struct' do
      before do
        test_object.instance_variable_set(:@metastruct, preexisting_metastruct)
        test_object.deep_merge_metastruct!(new_metastruct)
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
