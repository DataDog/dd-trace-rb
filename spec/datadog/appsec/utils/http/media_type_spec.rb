require 'datadog/appsec/utils/http/media_type'

RSpec.describe Datadog::AppSec::Utils::HTTP::MediaType do
  describe '.parse' do
    context 'when input is valid' do
      expectations = {
        '*/*' => {type: '*', subtype: '*'},
        'text/*' => {type: 'text', subtype: '*'},
        'text/html' => {type: 'text', subtype: 'html'},
        'Text/HTML' => {type: 'text', subtype: 'html'},
        'text/plain;format=flowed' => {type: 'text', subtype: 'plain', parameters: {'format' => 'flowed'}},
        'Text/PLAIN;FORMAT=FLOWED' => {type: 'text', subtype: 'plain', parameters: {'format' => 'flowed'}},
        'text/plain ; format=flowed' => {type: 'text', subtype: 'plain', parameters: {'format' => 'flowed'}},
        'text/plain; format=flowed' => {type: 'text', subtype: 'plain', parameters: {'format' => 'flowed'}},
        'text/plain ;format=flowed' => {type: 'text', subtype: 'plain', parameters: {'format' => 'flowed'}},
        'application/json' => {type: 'application', subtype: 'json'},
        'application/x-www-form-urlencoded' => {type: 'application', subtype: 'x-www-form-urlencoded'},
        'image/svg+xml' => {type: 'image', subtype: 'svg+xml'},
        'application/vnd.api+json' => {type: 'application', subtype: 'vnd.api+json'},
        'application/hal+json' => {type: 'application', subtype: 'hal+json'},
        'application/vnd.datadog.trace.v1+msgpack' => {type: 'application', subtype: 'vnd.datadog.trace.v1+msgpack'},
        'text/html;charset=utf-8;boundary=something' => {
          type: 'text',
          subtype: 'html',
          parameters: {'charset' => 'utf-8', 'boundary' => 'something'}
        },
        'multipart/form-data;boundary=----WebKitFormBoundary' => {
          type: 'multipart',
          subtype: 'form-data',
          parameters: {'boundary' => '----webkitformboundary'}
        },
        'text/plain;charset="utf-8"' => {type: 'text', subtype: 'plain', parameters: {'charset' => 'utf-8'}},
        'text/plain;boundary="----=_Part_0"' => {type: 'text', subtype: 'plain', parameters: {'boundary' => '----=_part_0'}},
        'text/plain;foo="bar";baz=qux' => {
          type: 'text',
          subtype: 'plain',
          parameters: {'foo' => 'bar', 'baz' => 'qux'}
        },
      }

      expectations.each do |str, expected|
        it "parses #{str.inspect} to #{expected.inspect}" do
          expect(described_class.parse(str)).to have_attributes(expected)
        end
      end
    end

    context 'when input is invalid' do
      invalid_inputs = [
        'text/html ',
        ' text/html',
        'text /html',
        'text/ html',
        'text/plain;format = flowed',
        'text/plain;format= flowed',
        'text/plain;format =flowed',
        '',
        'text',
        '/html',
        'text/',
        '/',
        'text/html;',
        'text/html;;charset=utf-8',
        'text/html;charset',
        'text/html;=utf-8',
        nil,
      ]

      invalid_inputs.each do |str|
        it "returns nil for #{str.inspect}" do
          expect(described_class.parse(str)).to be_nil
        end
      end
    end
  end

  describe '#type' do
    it { expect(described_class.parse('text/html').type).to eq('text') }
    it { expect(described_class.parse('APPLICATION/JSON').type).to eq('application') }
    it { expect(described_class.parse('*/html').type).to eq('*') }
  end

  describe '#subtype' do
    it { expect(described_class.parse('text/html').subtype).to eq('html') }
    it { expect(described_class.parse('text/HTML').subtype).to eq('html') }
    it { expect(described_class.parse('text/*').subtype).to eq('*') }
    it { expect(described_class.parse('application/vnd.api+json').subtype).to eq('vnd.api+json') }
  end

  describe '#parameters' do
    it { expect(described_class.parse('text/html').parameters).to eq({}) }
    it { expect(described_class.parse('text/html;charset=utf-8').parameters).to eq({'charset' => 'utf-8'}) }
    it { expect(described_class.parse('text/html;a=1;b=2').parameters).to eq({'a' => '1', 'b' => '2'}) }
  end

  describe '#to_s' do
    expectations = {
      'text/html' => 'text/html',
      'application/json' => 'application/json',
      'application/x-www-form-urlencoded' => 'application/x-www-form-urlencoded',
      'text/plain;format=flowed' => 'text/plain;format=flowed',
      'Text/HTML' => 'text/html',
      'text/html;charset=utf-8;boundary=foo' => 'text/html;charset=utf-8;boundary=foo',
      'application/vnd.api+json' => 'application/vnd.api+json',
    }

    expectations.each do |media, expected|
      it "converts #{media.inspect} to #{expected.inspect}" do
        expect(described_class.parse(media).to_s).to eq(expected)
      end
    end
  end
end
