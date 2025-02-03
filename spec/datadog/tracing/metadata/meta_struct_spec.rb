require 'datadog/tracing/metadata/meta_struct'

RSpec.describe Datadog::Tracing::Metadata::MetaStruct do
  subject(:test_object) { test_class.new }
  let(:test_class) { Class.new { include Datadog::Tracing::Metadata::MetaStruct } }

  describe '#set_meta_struct' do
    subject(:meta_struct_instance_var) { test_object.send(:meta_struct) }

    context 'when setting meta struct' do
      before do
        test_object.instance_variable_set(:@meta_struct, preexisting_meta_struct)
        test_object.set_meta_struct(meta_struct)
      end

      let(:preexisting_meta_struct) { nil }

      context 'with empty preexisting meta_struct' do
        let(:meta_struct) { { 'key' => 'value' } }

        it { is_expected.to eq({ 'key' => 'value' }) }
      end

      context 'with preexisting meta_struct' do
        let(:preexisting_meta_struct) { { 'old_key' => 'old_value' } }

        context 'with new key' do
          let(:meta_struct) { { 'new_key' => 'new_value' } }

          it { is_expected.to eq({ 'old_key' => 'old_value', 'new_key' => 'new_value' }) }
        end

        context 'with existing key' do
          let(:meta_struct) { { 'old_key' => 'new_value' } }

          it { is_expected.to eq({ 'old_key' => 'new_value' }) }
        end
      end
    end
  end
end
