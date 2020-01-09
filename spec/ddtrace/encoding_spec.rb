require 'spec_helper'

require 'ddtrace/encoding'

RSpec.describe Datadog::Encoding::JSONEncoder::V2 do
  def compare_arrays(left = [], right = [])
    left.zip(right).each { |tuple| yield(*tuple) }
  end

  describe '::encode_traces' do
    subject(:encode_traces) { described_class.encode_traces(traces) }
    let(:traces) { get_test_traces(2) }

    it { is_expected.to be_a_kind_of(String) }

    describe 'produces a JSON schema' do
      subject(:schema) { JSON.parse(encode_traces) }

      it 'which is wrapped' do
        is_expected.to be_a_kind_of(Hash)
        is_expected.to include('traces' => kind_of(Array))
      end

      describe 'whose encoded traces' do
        subject(:encoded_traces) { schema['traces'] }

        it 'contains the traces' do
          is_expected.to have(traces.length).items
        end

        it 'has IDs that are hex encoded' do
          compare_arrays(traces, encoded_traces) do |trace, encoded_trace|
            compare_arrays(trace, encoded_trace) do |span, encoded_span|
              described_class::ENCODED_IDS.each do |id|
                encoded_id = encoded_span[id.to_s].to_i(16)
                original_id = span.send(id)
                expect(encoded_id).to eq(original_id)
              end
            end
          end
        end
      end
    end
  end
end
