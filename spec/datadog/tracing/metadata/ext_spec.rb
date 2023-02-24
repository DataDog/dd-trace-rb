require 'spec_helper'

require 'datadog/tracing/metadata/ext'

RSpec.describe Datadog::Tracing::Metadata::Ext::HTTP::Headers do
  describe '.to_tag' do
    subject(:to_tag) { described_class.to_tag(tag) }

    context 'with alphanumeric characters' do
      let(:tag) { 'MyTag01' }

      it 'converts them to lowercase' do
        is_expected.to eq('mytag01')
      end
    end

    context 'with a period' do
      let(:tag) { 'a.b.' }

      it 'replaces period with underscore' do
        is_expected.to eq('a_b_')
      end
    end

    context 'with supported special characters' do
      let(:tag) { '_-:/' }

      it 'preserves them' do
        is_expected.to eq(tag)
      end
    end

    context 'with unsupported characters' do
      let(:tag) { "\\ \t!@?" }

      it 'replaces each with an underscore' do
        is_expected.to eq('_' * tag.size)
      end
    end
  end
end
