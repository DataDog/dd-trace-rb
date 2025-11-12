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
        is_expected.to eq("")
      end
    end

    context 'with a mix of unsupported and supported characters' do
      let(:tag) { "\\ \t!@?a" }

      it 'the first letter to show up is the supported character' do
        is_expected.to eq('a')
      end
    end

    context 'with all unsupported characters' do
      let(:tag) { "\\ \t!@?" }

      it 'turns into an empty string because the first character must be a letter' do
        is_expected.to eq('')
      end
    end

    context 'with `allow_nested: true`' do
      subject(:to_tag) { described_class.to_tag(tag, allow_nested: true) }

      context 'with a period' do
        let(:tag) { 'a.b.' }

        it 'does not replace period with underscore' do
          is_expected.to eq('a.b.')
        end
      end
    end
  end
end
