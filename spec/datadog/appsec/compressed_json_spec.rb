# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/compressed_json'

RSpec.describe Datadog::AppSec::CompressedJson do
  before { allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry) }

  let(:telemetry) { spy(Datadog::Core::Telemetry::Component) }

  describe '.dump' do
    context 'when payload is nil' do
      it { expect(described_class.dump(nil)).to eq('null') }
    end

    context 'when payload is small' do
      before { stub_const('Datadog::AppSec::CompressedJson::MIN_SIZE_FOR_COMPRESSION', 1000) }

      it { expect(described_class.dump({ foo: 'bar' })).to eq('{"foo":"bar"}') }
    end

    context 'when payload is large' do
      before { stub_const('Datadog::AppSec::CompressedJson::MIN_SIZE_FOR_COMPRESSION', 10) }

      it 'returns compressed data' do
        compressed = described_class.dump({ foo: 'block_request_and_redirect_to_login_page' })

        expect(compressed).to_not eq('{"foo":"block_request_and_redirect_to_login_page"}')
        expect(compressed).to match(%r{^[-A-Za-z0-9+/]*={0,3}$})
      end
    end

    context 'when JSON conversion fails' do
      before { allow(JSON).to receive(:dump).and_raise(ArgumentError) }

      it 'reports the error and returns nil' do
        expect(described_class.dump({ foo: 'something bad' })).to be_nil
        expect(Datadog::AppSec.telemetry).to have_received(:report)
      end
    end

    context 'when JSON dump fails' do
      it 'reports the error and returns nil' do
        expect(described_class.dump({ foo: "\xC2" })).to be_nil
        expect(Datadog::AppSec.telemetry).to have_received(:report)
      end
    end

    context 'when compression fails' do
      before do
        stub_const('Datadog::AppSec::CompressedJson::MIN_SIZE_FOR_COMPRESSION', 1)
        allow(Zlib).to receive(:gzip).and_raise(Zlib::DataError)
      end

      it 'reports the error and returns nil' do
        expect(described_class.dump({ foo: 'bar' })).to be_nil
        expect(Datadog::AppSec.telemetry).to have_received(:report)
      end
    end
  end
end
