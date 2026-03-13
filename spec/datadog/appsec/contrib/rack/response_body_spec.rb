# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rack/response_body'

RSpec.describe Datadog::AppSec::Contrib::Rack::ResponseBody do
  describe '.content_length' do
    context 'when body is a plain array with a single string' do
      let(:content_length) { described_class.content_length(['hello']) }

      it { expect(content_length).to eq(5) }
    end

    context 'when body is a plain array with multiple strings' do
      let(:content_length) { described_class.content_length(['hello', ' world']) }

      it { expect(content_length).to eq(11) }
    end

    context 'when body is an empty array' do
      let(:content_length) { described_class.content_length([]) }

      it { expect(content_length).to eq(0) }
    end

    context 'when body contains multibyte characters' do
      let(:content_length) { described_class.content_length(["\u00e9"]) }

      it { expect(content_length).to eq(2) }
    end

    context 'when body does not respond to to_ary' do
      let(:content_length) { described_class.content_length(['hello'].each) }

      it { expect(content_length).to be_nil }
    end

    context 'when body is a BodyProxy-like wrapper' do
      let(:content_length) do
        described_class.content_length(double('Rack::BodyProxy', to_ary: ['hello']))
      end

      it { expect(content_length).to eq(5) }
    end

    context 'when body.to_ary raises an error' do
      before do
        allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
        allow(body).to receive(:to_ary).and_raise(IOError, 'closed stream')
      end

      let(:content_length) { described_class.content_length(body) }
      let(:body) { double('Rack::BodyProxy', to_ary: nil) }
      let(:telemetry) { double('telemetry', report: nil) }

      it 'reports the error via telemetry' do
        expect(content_length).to be_nil

        expect(telemetry).to have_received(:report).with(
          kind_of(IOError),
          description: 'AppSec: Failed to compute body content length',
        )
      end
    end
  end
end
