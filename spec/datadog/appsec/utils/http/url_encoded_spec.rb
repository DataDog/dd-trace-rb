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

      it 'distinguishes keys without a value from keys with an empty value' do
        expect(described_class.parse('a&b=')).to eq({'a' => nil, 'b' => ''})
      end
    end

    context 'when payload has multi-byte UTF-8 characters' do
      it 'preserves raw multi-byte characters in keys and values' do
        expect(described_class.parse('naïve=café&clé=值')).to eq({'naïve' => 'café', 'clé' => '值'})
      end

      it 'decodes percent-encoded multi-byte characters' do
        expect(described_class.parse('q=%E5%80%A4')).to eq({'q' => '値'})
      end

      it 'drops the truncated pair without corrupting kept pairs when the limit falls inside a character' do
        expect(described_class.parse('aa=1&x=café', limit: 10)).to eq({'aa' => '1'})
      end
    end

    context 'when payload has empty pairs' do
      it { expect(described_class.parse('key=value&&foo=bar')).to eq({'key' => 'value', 'foo' => 'bar'}) }
      it { expect(described_class.parse('&key=value')).to eq({'key' => 'value'}) }
    end

    context 'when payload has value with equals sign' do
      it { expect(described_class.parse('key=a=b')).to eq({'key' => 'a=b'}) }
    end

    context 'when payload has malformed percent-encoding' do
      it { expect(described_class.parse('bad=%&payload=%3Cscript%3E')).to eq({'bad' => '%', 'payload' => '<script>'}) }
    end

    context 'when payload exceeds the bytesize limit' do
      it 'returns the fully-read pairs and omits the one crossing the limit' do
        expect(described_class.parse('a=1&b=2&c=3', limit: 9)).to eq({'a' => '1', 'b' => '2'})
      end

      it 'drops the pair that crosses the limit right before & separator' do
        expect(described_class.parse('a=1&b=2&c=3', limit: 7)).to eq({'a' => '1'})
      end

      it 'keeps the array entries read before the limit and drops the pair crossing it' do
        expect(described_class.parse('key=a&key=b&key=c', limit: 12)).to eq({'key' => ['a', 'b']})
      end

      it 'keeps a duplicate key as a string value when the limit drops the second value' do
        expect(described_class.parse('key=a&key=b', limit: 10)).to eq({'key' => 'a'})
      end
    end
  end
end
