# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/configuration/path'

RSpec.describe Datadog::Core::Remote::Configuration::Path do
  describe '.parse' do
    let(:product) { SecureRandom.hex }
    let(:config_id) { SecureRandom.hex }
    let(:name) { SecureRandom.hex }

    let(:components) do
      [source, org_id, product, config_id, name]
    end

    let(:input) { components.compact.join('/') }

    shared_examples 'a parsed path' do
      subject(:path) { described_class.parse(input) }

      let(:expected_attrs) do
        {
          source: source,
          org_id: org_id.nil? ? org_id : Integer(org_id),
          product: product,
          config_id: config_id,
          name: name,
        }
      end

      it 'returns a Path instance' do
        expect(path).to be_a(described_class)
      end

      it 'has attributes parsed' do
        expect(path).to have_attributes(expected_attrs)
      end
    end

    shared_examples 'parsing failed' do
      it 'raises ParseError' do
        expect { described_class.parse(input) }.to raise_error(described_class::ParseError)
      end
    end

    shared_examples 'invalid rest parsing failed' do
      context 'with missing product' do
        let(:product) { nil }

        it_behaves_like 'parsing failed'
      end

      context 'with missing config_id' do
        let(:config_id) { nil }

        it_behaves_like 'parsing failed'
      end

      context 'with missing name' do
        let(:name) { nil }

        it_behaves_like 'parsing failed'
      end

      context 'with too many components' do
        let(:input) { (components << 'extra').compact.join('/') }

        it_behaves_like 'parsing failed'
      end
    end

    context 'without a source' do
      let(:source) { nil }

      context 'with an org id' do
        let(:org_id) { '42' }

        it_behaves_like 'parsing failed'
      end

      context 'without an org id' do
        let(:org_id) { nil }

        it_behaves_like 'parsing failed'
      end
    end

    context 'with a datadog source' do
      let(:source) { 'datadog' }

      context 'and an org id' do
        let(:org_id) { '42' }

        it_behaves_like 'a parsed path'
        it_behaves_like 'invalid rest parsing failed'
      end

      context 'with a non-integer org id' do
        let(:org_id) { 'abc' }

        it_behaves_like 'parsing failed'
      end

      context 'without an org id' do
        let(:org_id) { nil }

        it_behaves_like 'parsing failed'
      end
    end

    context 'with an employee source' do
      let(:source) { 'employee' }

      context 'without an org id' do
        let(:org_id) { nil }

        it_behaves_like 'a parsed path'
        it_behaves_like 'invalid rest parsing failed'
      end

      context 'and an org id' do
        let(:org_id) { '42' }

        it_behaves_like 'parsing failed'
      end
    end
  end

  describe '#to_s' do
    subject(:path) { described_class.parse(input).to_s }

    context 'with a datadog source' do
      let(:input) { 'datadog/123/ASM/blocked_ips/config' }

      it { is_expected.to eq(input) }
    end

    context 'with an employee source' do
      let(:input) { 'employee/ASM/blocked_ips/config' }

      it { is_expected.to eq(input) }
    end
  end

  describe '#==' do
    subject(:path) { described_class.parse('datadog/42/BAR/baz/quz') }

    let(:other_path) { described_class.parse('datadog/43/BAR/baz/quz') }

    it { is_expected.to eq(path) }
    it { is_expected.to eq(path.dup) }
    it { is_expected.to_not eq(other_path) }
  end

  describe '#eql?' do
    subject(:path) { described_class.parse('datadog/42/BAR/baz/quz') }

    let(:other_path) { described_class.parse('datadog/43/BAR/baz/quz') }

    it { is_expected.to be_eql(path) }
    it { is_expected.to be_eql(path.dup) }
    it { is_expected.to_not be_eql(other_path) }
  end
end
