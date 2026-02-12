# frozen_string_literal: true

require 'datadog/appsec/utils/http/url_encoded'

RSpec.describe Datadog::AppSec::Utils::HTTP::URLEncoded do
  describe '.parse' do
    context 'when payload is nil' do
      it { expect(described_class.parse(nil)).to eq({}) }
    end

    context 'when payload is empty' do
      it { expect(described_class.parse('')).to eq({}) }
    end

    context 'when payload has single key-value pair' do
      it { expect(described_class.parse('key=value')).to eq({'key' => 'value'}) }
    end

    context 'when payload has multiple key-value pairs' do
      it { expect(described_class.parse('key=value&foo=bar')).to eq({'key' => 'value', 'foo' => 'bar'}) }
    end

    context 'when payload has duplicate keys' do
      it { expect(described_class.parse('key=a&key=b')).to eq({'key' => ['a', 'b']}) }
      it { expect(described_class.parse('key=a&key=b&key=c')).to eq({'key' => ['a', 'b', 'c']}) }
    end

    context 'when payload has encoded values' do
      it { expect(described_class.parse('key=hello%20world')).to eq({'key' => 'hello world'}) }
      it { expect(described_class.parse('key=hello+world')).to eq({'key' => 'hello world'}) }
      it { expect(described_class.parse('key%3D=value')).to eq({'key=' => 'value'}) }
    end

    context 'when payload has key without value' do
      it { expect(described_class.parse('key')).to eq({'key' => nil}) }
      it { expect(described_class.parse('key=')).to eq({'key' => ''}) }
    end

    context 'when payload has empty pairs' do
      it { expect(described_class.parse('key=value&&foo=bar')).to eq({'key' => 'value', 'foo' => 'bar'}) }
      it { expect(described_class.parse('&key=value')).to eq({'key' => 'value'}) }
    end

    context 'when payload has value with equals sign' do
      it { expect(described_class.parse('key=a=b')).to eq({'key' => 'a=b'}) }
    end
  end
end
