# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/transport/http/adapters/net'

RSpec.describe Datadog::Core::Transport::HTTP::Adapters::Net::Response do
  subject(:response) { described_class.new(http_response) }

  let(:http_response) { double('Net::HTTPResponse') }

  describe '#too_many_requests?' do
    subject(:too_many_requests?) { response.too_many_requests? }

    context 'when http_response is nil' do
      let(:http_response) { nil }

      it { is_expected.to be_nil }
    end

    context 'when status code is 429' do
      before do
        allow(http_response).to receive(:code).and_return('429')
      end

      it { is_expected.to be true }
    end

    context 'when status code is 200' do
      before do
        allow(http_response).to receive(:code).and_return('200')
      end

      it { is_expected.to be false }
    end

    context 'when status code is 400' do
      before do
        allow(http_response).to receive(:code).and_return('400')
      end

      it { is_expected.to be false }
    end

    context 'when status code is 500' do
      before do
        allow(http_response).to receive(:code).and_return('500')
      end

      it { is_expected.to be false }
    end
  end
end
