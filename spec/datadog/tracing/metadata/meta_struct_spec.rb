require 'datadog/tracing/metadata/metastruct'

RSpec.describe Datadog::Tracing::Metadata::Metastruct do
  subject(:test_object) { test_class.new }
  let(:test_class) { Class.new { include Datadog::Tracing::Metadata::Metastruct } }

  describe '#set_metastruct' do
    subject(:metastruct_instance_var) { test_object.send(:metastruct) }

    context 'when setting meta struct' do
      before do
        test_object.instance_variable_set(:@metastruct, preexisting_metastruct)
        test_object.set_metastruct(metastruct)
      end

      let(:preexisting_metastruct) { nil }

      context 'with empty preexisting metastruct' do
        let(:metastruct) { { 'key' => 'value' } }

        it { is_expected.to eq({ 'key' => 'value' }) }
      end

      context 'with preexisting metastruct' do
        let(:preexisting_metastruct) { { 'old_key' => 'old_value' } }

        context 'with new key' do
          let(:metastruct) { { 'new_key' => 'new_value' } }

          it { is_expected.to eq({ 'old_key' => 'old_value', 'new_key' => 'new_value' }) }
        end

        context 'with existing key' do
          let(:metastruct) { { 'old_key' => 'new_value' } }

          it { is_expected.to eq({ 'old_key' => 'new_value' }) }
        end
      end
    end
  end
end
