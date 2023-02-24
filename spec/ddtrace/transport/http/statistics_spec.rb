require 'spec_helper'

require 'ddtrace/transport/http/statistics'

RSpec.describe Datadog::Transport::HTTP::Statistics do
  context 'when implemented by a class' do
    subject(:object) { stats_class.new }

    let(:stats_class) do
      stub_const('TestObject', Class.new { include Datadog::Transport::HTTP::Statistics })
    end

    describe '#metrics_for_response' do
      subject(:metrics_for_response) { object.metrics_for_response(response) }

      let(:response) { instance_double(Datadog::Transport::HTTP::Response, code: status_code) }
      let(:status_code) { double('status code') }

      context 'when the response' do
        context 'is OK' do
          let(:status_code) { 200 }

          before do
            allow(response).to receive(:ok?).and_return(true)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          it do
            is_expected.to be_a_kind_of(Hash)
            is_expected.to have(1).item

            expect(metrics_for_response[:api_responses]).to have_attributes(
              type: :api_responses,
              name: nil,
              value: 1,
              options: { tags: ["status_code:#{response.code}"] }
            )
          end
        end

        context 'is a client error' do
          let(:status_code) { 400 }

          before do
            allow(response).to receive(:ok?).and_return(false)
            allow(response).to receive(:client_error?).and_return(true)
            allow(response).to receive(:server_error?).and_return(false)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          it do
            is_expected.to be_a_kind_of(Hash)
            is_expected.to have(1).item

            expect(metrics_for_response[:api_responses]).to have_attributes(
              type: :api_responses,
              name: nil,
              value: 1,
              options: { tags: ["status_code:#{response.code}"] }
            )
          end
        end

        context 'is a server error' do
          let(:status_code) { 500 }

          before do
            allow(response).to receive(:ok?).and_return(false)
            allow(response).to receive(:client_error?).and_return(false)
            allow(response).to receive(:server_error?).and_return(true)
            allow(response).to receive(:internal_error?).and_return(false)
          end

          it do
            is_expected.to be_a_kind_of(Hash)
            is_expected.to have(1).item

            expect(metrics_for_response[:api_responses]).to have_attributes(
              type: :api_responses,
              name: nil,
              value: 1,
              options: { tags: ["status_code:#{response.code}"] }
            )
          end
        end

        context 'is an internal error' do
          before do
            allow(response).to receive(:ok?).and_return(false)
            allow(response).to receive(:client_error?).and_return(false)
            allow(response).to receive(:server_error?).and_return(false)
            allow(response).to receive(:internal_error?).and_return(true)
          end

          it do
            is_expected.to be_a_kind_of(Hash)
            is_expected.to have(1).item

            expect(metrics_for_response[:api_errors]).to have_attributes(
              type: :api_errors,
              name: nil,
              value: 1
            )
          end
        end
      end
    end
  end
end
