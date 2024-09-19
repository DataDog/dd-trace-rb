require 'spec_helper'

require 'datadog/tracing/distributed/datadog_tags_codec'

RSpec.describe Datadog::Tracing::Distributed::DatadogTagsCodec do
  let(:codec) { described_class }

  describe '#decode' do
    subject(:decode) { codec.decode(input) }

    context 'with a valid input' do
      [
        ['', {}],
        ['key=value', { 'key' => 'value' }],
        ['_key=value', { '_key' => 'value' }],
        ['1key=digit', { '1key' => 'digit' }],
        ['12345=678910', { '12345' => '678910' }],
        ['trailing=comma,', { 'trailing' => 'comma' }],
        ['value=with spaces', { 'value' => 'with spaces' }],
        ['value=with=equals', { 'value' => 'with=equals' }],
        ['trim= value ', { 'trim' => 'value' }],
        ['ascii@=~chars;', { 'ascii@' => '~chars;' }],
        ['a=1,b=2,c=3', { 'a' => '1', 'b' => '2', 'c' => '3' }],
      ].each do |input, expected|
        context "of value `#{input}`" do
          let(:input) { input }
          it { is_expected.to eq(expected) }
        end
      end
    end

    context 'with an invalid input' do
      [
        'no_equals',
        'no_value=',
        '=no_key',
        '=',
        ',',
        ',=,',
        ',leading=comma',
        'key with=spaces',
        "out_of=range\ncharacter",
        "out\tof=range character",
      ].each do |input|
        context "of value `#{input}`" do
          let(:input) { input }
          it { expect { decode }.to raise_error(Datadog::Tracing::Distributed::DatadogTagsCodec::DecodingError) }
        end
      end
    end
  end

  describe '#encode' do
    subject(:encode) { codec.encode(input) }

    context 'with a valid input' do
      [
        [{}, ''],
        [{ 'key' => 'value' }, 'key=value'],
        [{ 'key' => 1 }, 'key=1'],
        [{ 'a' => '1', 'b' => '2', 'c' => '3' }, 'a=1,b=2,c=3'],
        [{ 'trim' => ' value ' }, 'trim=value'],
      ].each do |input, expected|
        context "of value `#{input}`" do
          let(:input) { input }
          it { is_expected.to eq(expected) }
        end
      end
    end

    context 'with an invalid input' do
      [
        { 'key with' => 'space' },
        { 'key,with' => 'comma' },
        { 'value' => 'with,comma' },
        { 'key=with' => 'equals' },
        { '' => 'empty_key' },
        { 'empty_value' => '' },
        { '🙅️' => 'out of range characters' },
        { 'out_of_range_characters' => '🙅️' },
      ].each do |input, _expected|
        context "of value `#{input}`" do
          let(:input) { input }
          it { expect { encode }.to raise_error(Datadog::Tracing::Distributed::DatadogTagsCodec::EncodingError) }
        end
      end
    end
  end

  describe 'encode and decode' do
    let(:input) do
      { 'key' => 'value' }
    end

    let(:encoded_input) do
      'key=value'
    end

    it 'decoding reverses encoding' do
      expect(codec.decode(codec.encode(input))).to eq(input)
    end

    it 'encoding reverses decoding' do
      expect(codec.encode(codec.decode(encoded_input))).to eq(encoded_input)
    end
  end
end
