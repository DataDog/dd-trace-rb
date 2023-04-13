require 'datadog/appsec/utils/http/media_range'

RSpec.describe Datadog::AppSec::Utils::HTTP::MediaRange do
  describe '.new' do
    context 'with valid input' do
      # rubocop:disable Layout/LineLength
      expectations = {
        '*/*' => { type: '*', subtype: '*', quality: 1.0, parameters: {}, accept_ext: {} },
        'text/*' => { type: 'text', subtype: '*', parameters: {}, accept_ext: {} },
        'text/html' => { type: 'text', subtype: 'html', quality: 1.0, parameters: {}, accept_ext: {} },
        'Text/HTML' => { type: 'text', subtype: 'html', quality: 1.0, parameters: {}, accept_ext: {} },
        'application/json' => { type: 'application', subtype: 'json', parameters: {}, accept_ext: {} },
        'text/html;Q=1' => { type: 'text', subtype: 'html', quality: 1.0, parameters: {}, accept_ext: {} },
        'text/html;q=1' => { type: 'text', subtype: 'html', quality: 1.0, parameters: {}, accept_ext: {} },
        'text/html;q=1.0' => { type: 'text', subtype: 'html', quality: 1.0, parameters: {}, accept_ext: {} },
        'text/html;q=1.00' => { type: 'text', subtype: 'html', quality: 1.0, parameters: {}, accept_ext: {} },
        'text/html;q=1.000' => { type: 'text', subtype: 'html', quality: 1.0, parameters: {}, accept_ext: {} },
        'text/html;q=0.5' => { type: 'text', subtype: 'html', quality: 0.5, parameters: {}, accept_ext: {} },
        'text/html;q=0.333' => { type: 'text', subtype: 'html', quality: 0.333, parameters: {}, accept_ext: {} },
        'text/html;q=0' => { type: 'text', subtype: 'html', quality: 0.0, parameters: {}, accept_ext: {} },
        'text/html;q=0.0' => { type: 'text', subtype: 'html', quality: 0.0, parameters: {}, accept_ext: {} },
        'text/html;q=0.00' => { type: 'text', subtype: 'html', quality: 0.0, parameters: {}, accept_ext: {} },
        'text/html;q=0.000' => { type: 'text', subtype: 'html', quality: 0.0, parameters: {}, accept_ext: {} },
        'Text/HTML;FOO=BAR' => { type: 'text', subtype: 'html', quality: 1.0, parameters: { 'foo' => 'bar' }, accept_ext: {} },
        'text/html;foo=bar' => { type: 'text', subtype: 'html', quality: 1.0, parameters: { 'foo' => 'bar' }, accept_ext: {} },
        'text/html ; foo=bar' => { type: 'text', subtype: 'html', quality: 1.0, parameters: { 'foo' => 'bar' }, accept_ext: {} },
        'text/html; foo=bar' => { type: 'text', subtype: 'html', quality: 1.0, parameters: { 'foo' => 'bar' }, accept_ext: {} },
        'text/html ;foo=bar' => { type: 'text', subtype: 'html', quality: 1.0, parameters: { 'foo' => 'bar' }, accept_ext: {} },
        'text/html;foo="bar"' => { type: 'text', subtype: 'html', quality: 1.0, parameters: { 'foo' => 'bar' }, accept_ext: {} },
        'text/html;foo=bar;baz=qux' => { type: 'text', subtype: 'html', quality: 1.0, parameters: { 'foo' => 'bar', 'baz' => 'qux' }, accept_ext: {} },
        'text/html;foo="bar";baz="qux"' => { type: 'text', subtype: 'html', quality: 1.0, parameters: { 'foo' => 'bar', 'baz' => 'qux' }, accept_ext: {} },
        'text/html;q=0.5;foo=bar' => { type: 'text', subtype: 'html', quality: 0.5, parameters: {}, accept_ext: { 'foo' => 'bar' } },
        'text/html;q=0.5;foo="bar"' => { type: 'text', subtype: 'html', quality: 0.5, parameters: {}, accept_ext: { 'foo' => 'bar' } },
        'text/html;q=0.5;foo=bar;baz=qux' => { type: 'text', subtype: 'html', quality: 0.5, parameters: {}, accept_ext: { 'foo' => 'bar', 'baz' => 'qux' } },
        'text/html;q=0.5;foo="bar";baz="qux"' => { type: 'text', subtype: 'html', quality: 0.5, parameters: {}, accept_ext: { 'foo' => 'bar', 'baz' => 'qux' } },
        'text/html;foo=bar;q=0.5' => { type: 'text', subtype: 'html', quality: 0.5, parameters: { 'foo' => 'bar' }, accept_ext: {} },
        'text/html;foo="bar";q=0.5' => { type: 'text', subtype: 'html', quality: 0.5, parameters: { 'foo' => 'bar' }, accept_ext: {} },
        'text/html;foo=bar;baz=qux;q=0.5' => { type: 'text', subtype: 'html', quality: 0.5, parameters: { 'foo' => 'bar', 'baz' => 'qux' }, accept_ext: {} },
        'text/html;foo="bar";baz="qux";q=0.5' => { type: 'text', subtype: 'html', quality: 0.5, parameters: { 'foo' => 'bar', 'baz' => 'qux' }, accept_ext: {} },
        'text/html;foo=bar;q=0.5;baz=qux' => { type: 'text', subtype: 'html', quality: 0.5, parameters: { 'foo' => 'bar' }, accept_ext: { 'baz' => 'qux' } },
        'text/html;foo="bar";q=0.5;baz="qux"' => { type: 'text', subtype: 'html', quality: 0.5, parameters: { 'foo' => 'bar' }, accept_ext: { 'baz' => 'qux' } },
      }
      # rubocop:enable Layout/LineLength

      expectations.each do |str, expected|
        it "parses #{str.inspect} to #{expected.inspect}" do
          expect(described_class.new(str)).to have_attributes expected
        end
      end
    end

    context 'with invalid input' do
      parse_error = described_class::ParseError
      expectations = {
        'text/html ' => parse_error,
        ' text/html' => parse_error,
        'text /html' => parse_error,
        'text/ html' => parse_error,
        'text/html;q=' => parse_error,
        'text/html;q=1;' => parse_error,
        'text/html;q=1.0000' => parse_error,
        'text/html;q=1.001' => parse_error,
        'text/html;q=0.0000' => parse_error,
        'text/html;q=0.0001' => parse_error,
        'text/html;foo =bar' => parse_error,
        'text/html;foo= bar' => parse_error,
        'text/html;foo=bar;' => parse_error,
        'text/html;foo=bar"' => parse_error,
        'text/html;foo="bar' => parse_error,
        'text/html;foo="bar""' => parse_error,
      }

      expectations.each do |str, expected|
        it "raises #{expected} with #{str.inspect}" do
          expect { described_class.new(str) }.to raise_error(expected)
        end
      end
    end
  end

  describe '#to_s' do
    expectations = {
      '*/*' => '*/*',
      'text/*' => 'text/*',
      'text/html' => 'text/html',
      'application/json' => 'application/json',
      'text/html;q=1' => 'text/html',
      'text/html;q=1.0' => 'text/html',
      'text/html;q=1.00' => 'text/html',
      'text/html;q=1.000' => 'text/html',
      'text/html;q=0.5' => 'text/html;q=0.5',
      'text/html;q=0.333' => 'text/html;q=0.333',
      'text/html;q=0' => 'text/html;q=0.0',
      'text/html;q=0.0' => 'text/html;q=0.0',
      'text/html;q=0.00' => 'text/html;q=0.0',
      'text/html;q=0.000' => 'text/html;q=0.0',
      'text/html;foo=bar' => 'text/html;foo=bar',
      'text/html;foo="bar"' => 'text/html;foo=bar',
      'text/html;foo=bar;baz=qux' => 'text/html;foo=bar;baz=qux',
      'text/html;foo="bar";baz="qux"' => 'text/html;foo=bar;baz=qux',
      'text/html;q=0.5;foo=bar' => 'text/html;q=0.5;foo=bar',
      'text/html;q=0.5;foo="bar"' => 'text/html;q=0.5;foo=bar',
      'text/html;q=0.5;foo=bar;baz=qux' => 'text/html;q=0.5;foo=bar;baz=qux',
      'text/html;q=0.5;foo="bar";baz="qux"' => 'text/html;q=0.5;foo=bar;baz=qux',
      'text/html;foo=bar;q=0.5' => 'text/html;foo=bar;q=0.5',
      'text/html;foo="bar";q=0.5' => 'text/html;foo=bar;q=0.5',
      'text/html;foo=bar;baz=qux;q=0.5' => 'text/html;foo=bar;baz=qux;q=0.5',
      'text/html;foo="bar";baz="qux";q=0.5' => 'text/html;foo=bar;baz=qux;q=0.5',
      'text/html;foo=bar;q=0.5;baz=qux' => 'text/html;foo=bar;q=0.5;baz=qux',
      'text/html;foo="bar";q=0.5;baz="qux"' => 'text/html;foo=bar;q=0.5;baz=qux',
    }

    expectations.each do |str, expected|
      it "returns #{expected.inspect} for #{str.inspect}" do
        expect(described_class.new(str).to_s).to eq expected
      end
    end
  end

  describe '#wildcard?' do
    expectations = {
      '*/*' => true,
      'text/*' => true,
      'text/html' => false,
    }

    expectations.each do |str, expected|
      it "returns #{expected.inspect} for #{str.inspect}" do
        expect(described_class.new(str).wildcard?).to eq expected
      end
    end

    context 'for type' do
      expectations = {
        '*/*' => true,
        'text/*' => false,
        'text/html' => false,
      }

      expectations.each do |str, expected|
        it "returns #{expected.inspect} for #{str.inspect}" do
          expect(described_class.new(str).wildcard?(:type)).to eq expected
        end
      end
    end

    context 'for subtype' do
      expectations = {
        '*/*' => true,
        'text/*' => true,
        'text/html' => false,
      }

      expectations.each do |str, expected|
        it "returns #{expected.inspect} for #{str.inspect}" do
          expect(described_class.new(str).wildcard?(:subtype)).to eq expected
        end
      end
    end
  end

  describe '#specificity' do
    expectations = {
      '*/*' => 0,
      'text/*' => 0,
      'text/html' => 0,
      'text/html;foo=bar' => 1,
      'text/html;foo=bar;baz=qux' => 2,
      'text/html;q=0.5;foo=bar' => 0,
      'text/html;foo=bar;q=0.5' => 1,
      'text/html;q=0.5;foo=bar;baz=qux' => 0,
      'text/html;foo=bar;q=0.5;baz=qux' => 1,
      'text/html;foo=bar;baz=qux;q=0.5' => 2,
    }

    expectations.each do |str, expected|
      it "returns #{expected.inspect} for #{str.inspect}" do
        expect(described_class.new(str).specificity).to eq expected
      end
    end
  end

  describe '#<=>' do
    expectations = {
      # quality
      [
        'text/html',
        'text/html',
      ] => 0,
      [
        'text/html',
        'application/json',
      ] => 0,
      [
        'text/html',
        'application/json;q=0.5',
      ] => 1,
      [
        'text/html;q=0.5',
        'application/json',
      ] => -1,

      # specificity
      [
        'text/plain;format=flowed',
        'text/plain',
      ] => 1,
      [
        'text/plain',
        'text/plain;format=flowed',
      ] => -1,

      # quality/specificity mix
      [
        'text/plain;format=flowed;q=0.5',
        'text/plain',
      ] => -1,
      [
        'text/plain',
        'text/plain;format=flowed;q=0.5',
      ] => 1,

      # quality/extension mix
      [
        'text/plain;q=0.5;foo=bar',
        'text/plain',
      ] => -1,
      [
        'text/plain',
        'text/plain;q=0.5;foo=bar',
      ] => 1,

      # quality/specificity/extension mix
      [
        'text/plain;format=flowed;q=0.5;foo=bar',
        'text/plain',
      ] => -1,
      [
        'text/plain',
        'text/plain;format=flowed;q=0.5;foo=bar',
      ] => 1,

      # wildcard
      [
        '*/*',
        '*/*',
      ] => 0,
      [
        '*/*',
        'text/html',
      ] => -1,
      [
        'text/html',
        '*/*',
      ] => 1,
    }

    expectations.each do |(str1, str2), expected|
      it "returns #{expected.inspect} for #{str1.inspect} <=> #{str2.inspect}" do
        expect(described_class.new(str1) <=> described_class.new(str2)).to eq expected
      end
    end

    context 'using sort' do
      expectations = {
        [
          'audio/*;q=0.2',
          'audio/basic',
        ] => [
          'audio/*;q=0.2',
          'audio/basic',
        ],
        [
          'text/plain;q=0.5',
          'text/html',
          'text/x-dvi;q=0.8',
          'text/x-c',
        ] => [
          'text/plain;q=0.5',
          'text/x-dvi;q=0.8',
          'text/html',
          'text/x-c',
        ],
        [
          'text/*',
          'text/plain',
          'text/plain;format=flowed',
          '*/*',
        ] => [
          '*/*',
          'text/*',
          'text/plain',
          'text/plain;format=flowed',
        ],
        [
          'text/*;q=0.3',
          'text/html;q=0.7',
          'text/html;level=1',
          'text/html;level=2;q=0.4',
          '*/*;q=0.5',
        ] => [
          'text/*;q=0.3',
          'text/html;level=2;q=0.4',
          '*/*;q=0.5',
          'text/html;q=0.7',
          'text/html;level=1',
        ],
      }

      expectations.each do |array, expected|
        it "returns #{expected.inspect} for #{array.inspect}" do
          expect(array.map { |str| described_class.new(str) }.sort.map(&:to_s)).to eq expected
        end
      end
    end
  end

  describe '#===' do
    expectations = {
      [
        'text/html',
        'text/html',
      ] => true,
      [
        'text/html',
        'text/plain',
      ] => false,
      [
        'text/*',
        'text/plain',
      ] => true,
      [
        '*/*',
        'text/plain',
      ] => true,
      [
        'text/html;level=1',
        'text/html',
      ] => true,
      [
        'text/html;level=1',
        'text/plain',
      ] => false,
      [
        'text/html;q=0.5',
        'text/html',
      ] => true,
      [
        'text/html;q=0.5',
        'text/plain',
      ] => false,
      [
        'text/*;q=0.5',
        'text/plain',
      ] => true,
      [
        '*/*;q=0.5',
        'text/plain',
      ] => true,
      [
        'text/html;level=1',
        'text/html;level=1',
      ] => true,
      [
        'text/html',
        'text/html;level=1',
      ] => false,
      [
        'text/html;level=1;foo=bar',
        'text/html;level=1',
      ] => true,
      [
        'text/html;foo=bar;level=1',
        'text/html;level=1',
      ] => true,
      [
        'text/html',
        'text/html;level=1;foo=bar',
      ] => false,
    }

    expectations.each do |(range, type), expected|
      let(:type_class) { Datadog::AppSec::Utils::HTTP::MediaType }

      it "returns #{expected.inspect} for #{range.inspect} <=> #{type.inspect}" do
        expect(described_class.new(range) === type_class.new(type)).to eq expected
      end
    end
  end
end
