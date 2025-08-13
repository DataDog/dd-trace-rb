require 'spec_helper'

require 'datadog/core/transport/http/adapters/net'

RSpec.describe Datadog::Core::Transport::HTTP::Adapters::Net::Response do
  subject(:response) { described_class.new(http_response) }

  let(:http_response) { instance_double(::Net::HTTPResponse) }

  describe '#initialize' do
    it { is_expected.to have_attributes(http_response: http_response) }
  end

  describe '#payload' do
    subject(:payload) { response.payload }

    let(:http_response) { instance_double(::Net::HTTPResponse, body: double('body')) }

    it { is_expected.to be(http_response.body) }
  end

  describe '#code' do
    subject(:code) { response.code }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: '200') }

    it { is_expected.to eq(200) }
  end

  describe '#ok?' do
    subject(:ok?) { response.ok? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code is 199' do
      let(:code) { 199 }

      it { is_expected.to be false }
    end

    context 'when code is 200' do
      let(:code) { 200 }

      it { is_expected.to be true }
    end

    context 'when code is 299' do
      let(:code) { 299 }

      it { is_expected.to be true }
    end

    context 'when code is 300' do
      let(:code) { 300 }

      it { is_expected.to be false }
    end
  end

  describe '#unsupported?' do
    subject(:unsupported?) { response.unsupported? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code is 400' do
      let(:code) { 400 }

      it { is_expected.to be false }
    end

    context 'when code is 415' do
      let(:code) { 415 }

      it { is_expected.to be true }
    end
  end

  describe '#not_found?' do
    subject(:not_found?) { response.not_found? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code is 400' do
      let(:code) { 400 }

      it { is_expected.to be false }
    end

    context 'when code is 404' do
      let(:code) { 404 }

      it { is_expected.to be true }
    end
  end

  describe '#client_error?' do
    subject(:client_error?) { response.client_error? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code is 399' do
      let(:code) { 399 }

      it { is_expected.to be false }
    end

    context 'when code is 400' do
      let(:code) { 400 }

      it { is_expected.to be true }
    end

    context 'when code is 499' do
      let(:code) { 499 }

      it { is_expected.to be true }
    end

    context 'when code is 500' do
      let(:code) { 500 }

      it { is_expected.to be false }
    end
  end

  describe '#server_error?' do
    subject(:server_error?) { response.server_error? }

    let(:http_response) { instance_double(::Net::HTTPResponse, code: code) }

    context 'when code is 499' do
      let(:code) { 499 }

      it { is_expected.to be false }
    end

    context 'when code is 500' do
      let(:code) { 500 }

      it { is_expected.to be true }
    end

    context 'when code is 599' do
      let(:code) { 599 }

      it { is_expected.to be true }
    end

    context 'when code is 600' do
      let(:code) { 600 }

      it { is_expected.to be false }
    end
  end
end
