require 'datadog/appsec/utils/http/media_type'

RSpec.describe Datadog::AppSec::Utils::HTTP::MediaType do
  describe '.new' do
    context 'with valid input' do
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
        '' => parse_error,
        'text' => parse_error,
        '/html' => parse_error,
        'text/' => parse_error,
        '/' => parse_error,
        'text/html;' => parse_error,
        'text/html;;charset=utf-8' => parse_error,
        'text/html;charset' => parse_error,
        'text/html;=utf-8' => parse_error,
      }

      expectations.each do |str, expected|
        it "raises #{expected} with #{str.inspect}" do
          expect { described_class.new(str) }.to raise_error(expected)
        end
      end

      it 'raises ParseError with nil' do
        expect { described_class.new(nil) }.to raise_error(parse_error)
      end
    end
  end

  describe '#type' do
    it { expect(described_class.new('text/html').type).to eq('text') }
    it { expect(described_class.new('APPLICATION/JSON').type).to eq('application') }
    it { expect(described_class.new('*/html').type).to eq('*') }
  end

  describe '#subtype' do
    it { expect(described_class.new('text/html').subtype).to eq('html') }
    it { expect(described_class.new('text/HTML').subtype).to eq('html') }
    it { expect(described_class.new('text/*').subtype).to eq('*') }
    it { expect(described_class.new('application/vnd.api+json').subtype).to eq('vnd.api+json') }
  end

  describe '#parameters' do
    it { expect(described_class.new('text/html').parameters).to eq({}) }
    it { expect(described_class.new('text/html;charset=utf-8').parameters).to eq({'charset' => 'utf-8'}) }
    it { expect(described_class.new('text/html;a=1;b=2').parameters).to eq({'a' => '1', 'b' => '2'}) }
  end

  describe '#to_s' do
    expectations = {
      'text/html' => 'text/html',
      'application/json' => 'application/json',
      'application/x-www-form-urlencoded' => 'application/x-www-form-urlencoded',
      'multipart/form-data;boundary=WebKitFormBoundary' => 'multipart/form-data;boundary=webkitformboundary',
      'text/plain;format=flowed' => 'text/plain;format=flowed',
      'Text/HTML' => 'text/html',
      'text/html;charset=utf-8;boundary=foo' => 'text/html;charset=utf-8;boundary=foo',
      'application/vnd.api+json' => 'application/vnd.api+json',
    }

    expectations.each do |media, expected|
      it "converts #{media.inspect} to #{expected.inspect}" do
        expect(described_class.new(media).to_s).to eq(expected)
      end
    end
  end

  describe '.json?' do
    context 'when is a valid JSON media type' do
      it { expect(described_class.json?('application/json')).to be(true) }
      it { expect(described_class.json?('APPLICATION/JSON')).to be(true) }
      it { expect(described_class.json?('application/json; charset=utf-8')).to be(true) }
      it { expect(described_class.json?('application/hal+json')).to be(true) }
      it { expect(described_class.json?('application/vnd.api+json')).to be(true) }
      it { expect(described_class.json?('application/vnd.datadog+json')).to be(true) }
      it { expect(described_class.json?('text/json')).to be(true) }
    end

    context 'when is not a JSON media type' do
      it { expect(described_class.json?('text/html')).to be(false) }
      it { expect(described_class.json?('text/plain')).to be(false) }
      it { expect(described_class.json?('application/xml')).to be(false) }
      it { expect(described_class.json?('application/x-www-form-urlencoded')).to be(false) }
      it { expect(described_class.json?('multipart/form-data')).to be(false) }
    end

    context 'when is invalid media type' do
      it { expect(described_class.json?(nil)).to be(false) }
      it { expect(described_class.json?('')).to be(false) }
      it { expect(described_class.json?('invalid')).to be(false) }
      it { expect(described_class.json?('/')).to be(false) }
    end
  end

  describe '.form_urlencoded?' do
    context 'when is a valid form-urlencoded media type' do
      it { expect(described_class.form_urlencoded?('application/x-www-form-urlencoded')).to be(true) }
      it { expect(described_class.form_urlencoded?('APPLICATION/X-WWW-FORM-URLENCODED')).to be(true) }
      it { expect(described_class.form_urlencoded?('application/x-www-form-urlencoded; charset=utf-8')).to be(true) }
    end

    context 'when is not a form-urlencoded media type' do
      it { expect(described_class.form_urlencoded?('application/json')).to be(false) }
      it { expect(described_class.form_urlencoded?('text/plain')).to be(false) }
      it { expect(described_class.form_urlencoded?('multipart/form-data')).to be(false) }
    end

    context 'when is invalid media type' do
      it { expect(described_class.form_urlencoded?(nil)).to be(false) }
      it { expect(described_class.form_urlencoded?('')).to be(false) }
      it { expect(described_class.form_urlencoded?('invalid')).to be(false) }
    end
  end

  describe '.multipart_form_data?' do
    context 'when is a valid multipart/form-data media type' do
      it { expect(described_class.multipart_form_data?('multipart/form-data')).to be(true) }
      it { expect(described_class.multipart_form_data?('MULTIPART/FORM-DATA')).to be(true) }
      it { expect(described_class.multipart_form_data?('multipart/form-data; boundary=----WebKitFormBoundary')).to be(true) }
    end

    context 'when is not a multipart/form-data media type' do
      it { expect(described_class.multipart_form_data?('multipart/mixed')).to be(false) }
      it { expect(described_class.multipart_form_data?('application/json')).to be(false) }
      it { expect(described_class.multipart_form_data?('application/x-www-form-urlencoded')).to be(false) }
    end

    context 'when is invalid media type' do
      it { expect(described_class.multipart_form_data?(nil)).to be(false) }
      it { expect(described_class.multipart_form_data?('')).to be(false) }
      it { expect(described_class.multipart_form_data?('invalid')).to be(false) }
    end
  end
end
