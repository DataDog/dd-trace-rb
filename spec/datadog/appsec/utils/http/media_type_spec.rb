require 'datadog/appsec/utils/http/media_type'

RSpec.describe Datadog::AppSec::Utils::HTTP::MediaType do
  describe '.new' do
    context 'with valid input' do
      expectations = {
        '*/*' => { type: '*', subtype: '*' },
        'text/*' => { type: 'text', subtype: '*' },
        'text/html' => { type: 'text', subtype: 'html' },
        'Text/HTML' => { type: 'text', subtype: 'html' },
        'text/plain;format=flowed' => { type: 'text', subtype: 'plain', parameters: { 'format' => 'flowed' } },
        'Text/PLAIN;FORMAT=FLOWED' => { type: 'text', subtype: 'plain', parameters: { 'format' => 'flowed' } },
        'text/plain ; format=flowed' => { type: 'text', subtype: 'plain', parameters: { 'format' => 'flowed' } },
        'text/plain; format=flowed' => { type: 'text', subtype: 'plain', parameters: { 'format' => 'flowed' } },
        'text/plain ;format=flowed' => { type: 'text', subtype: 'plain', parameters: { 'format' => 'flowed' } },
        'application/json' => { type: 'application', subtype: 'json' },
      }

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
        'text/plain;format = flowed' => parse_error,
        'text/plain;format= flowed' => parse_error,
        'text/plain;format =flowed' => parse_error,
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
      'text/html' => 'text/html',
      'application/json' => 'application/json',
      'text/plain;format=flowed' => 'text/plain;format=flowed',
    }

    expectations.each do |str, expected|
      it "converts #{str.inspect} to #{expected.inspect}" do
        expect(described_class.new(str).to_s).to eq expected
      end
    end
  end
end
