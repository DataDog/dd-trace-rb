# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/utils/http/body'
require 'datadog/appsec/utils/http/media_type'

require 'stringio'
require 'tempfile'

RSpec.describe Datadog::AppSec::Utils::HTTP::Body do
  describe '.parse' do
    context 'when body is nil' do
      let(:media_type) do
        Datadog::AppSec::Utils::HTTP::MediaType.new(type: 'application', subtype: 'json')
      end
      let(:result) { described_class.parse(nil, media_type: media_type) }

      it { expect(result).to be_nil }
    end

    context 'when body is empty' do
      let(:media_type) do
        Datadog::AppSec::Utils::HTTP::MediaType.new(type: 'application', subtype: 'x-www-form-urlencoded')
      end
      let(:result) { described_class.parse('', media_type: media_type) }

      it { expect(result).to be_nil }
    end

    context 'when media type is application/json' do
      let(:media_type) do
        Datadog::AppSec::Utils::HTTP::MediaType.new(type: 'application', subtype: 'json')
      end

      context 'when body is a String' do
        let(:result) { described_class.parse('{"key":"value"}', media_type: media_type) }

        it { expect(result).to eq({'key' => 'value'}) }
      end

      context 'when body is a StringIO' do
        let(:result) { described_class.parse(StringIO.new('{"key":"value"}'), media_type: media_type) }

        it { expect(result).to eq({'key' => 'value'}) }
      end

      context 'when body is an IO object' do
        let(:tempfile) do
          Tempfile.new('body').tap do |f|
            f.write('{"key":"value"}')
            f.rewind
          end
        end
        let(:result) { described_class.parse(tempfile, media_type: media_type) }

        after { tempfile.close! }

        it { expect(result).to eq({'key' => 'value'}) }
      end

      context 'when body is invalid JSON' do
        before { allow(Datadog::AppSec.telemetry).to receive(:report) }

        let(:result) { described_class.parse('not json', media_type: media_type) }

        it 'returns nil and reports error to telemetry' do
          expect(result).to be_nil
          expect(Datadog::AppSec.telemetry).to have_received(:report)
            .with(an_instance_of(JSON::ParserError), description: 'AppSec: Failed to parse body')
        end
      end
    end

    context 'when media type is application/vnd.api+json' do
      let(:media_type) do
        Datadog::AppSec::Utils::HTTP::MediaType.new(type: 'application', subtype: 'vnd.api+json')
      end
      let(:result) { described_class.parse('{"data":"value"}', media_type: media_type) }

      it { expect(result).to eq({'data' => 'value'}) }
    end

    context 'when media type is application/x-www-form-urlencoded' do
      let(:media_type) do
        Datadog::AppSec::Utils::HTTP::MediaType.new(type: 'application', subtype: 'x-www-form-urlencoded')
      end

      context 'when body is a String' do
        let(:result) { described_class.parse('key=value&foo=bar', media_type: media_type) }

        it { expect(result).to eq({'key' => 'value', 'foo' => 'bar'}) }
      end

      context 'when body is a StringIO' do
        let(:result) { described_class.parse(StringIO.new('key=value'), media_type: media_type) }

        it { expect(result).to eq({'key' => 'value'}) }
      end
    end

    context 'when media type is unsupported' do
      let(:media_type) do
        Datadog::AppSec::Utils::HTTP::MediaType.new(type: 'text', subtype: 'plain')
      end
      let(:result) { described_class.parse('some text', media_type: media_type) }

      it { expect(result).to be_nil }
    end
  end
end
