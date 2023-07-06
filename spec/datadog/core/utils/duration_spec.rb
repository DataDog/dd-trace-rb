# frozen_string_literal: true

require 'datadog/core/utils/duration'

RSpec.describe Datadog::Core::Utils::Duration do
  describe '.call' do
    context 'with suffix' do
      context 'type integer' do
        let(:value) { '1h' }

        [
          [:s, 3600],
          [:ms, 3600000],
          [:us, 3600000000],
          [:ns, 3600000000000]
        ].each do |base, expected_value|
          context "custom base #{base}" do
            it 'parse value' do
              expect(described_class.call(value, base: base)).to eq(expected_value)
            end
          end
        end

        [
          ['minutes', '10m', :s, 600],
          ['seconds', '10s', :ms, 10000],
          ['miliseconds', '10ms', :us, 10000],
          ['microseconds', '10ns', :ns, 10],
          ['nanoseconds', '10us', :us, 10],
        ].each do |type, value, base, expected_value|
          context "support #{type}" do
            it 'parse value' do
              expect(described_class.call(value, base: base)).to eq(expected_value)
            end
          end
        end
      end

      context 'type float' do
        let(:value) { '1.5h' }

        [
          [:s, 5400],
          [:ms, 5400000],
          [:us, 5400000000],
          [:ns, 5400000000000]
        ].each do |base, expected_value|
          context "custom base #{base}" do
            it 'parse value' do
              expect(described_class.call(value, base: base)).to eq(expected_value)
            end
          end
        end

        [
          ['minutes', '10.5m', :s, 630],
          ['seconds', '10.5s', :ms, 10500],
          ['miliseconds', '10.5ms', :us, 10500],
          ['microseconds', '10.5ns', :ns, 11],
          ['nanoseconds', '10.5us', :us, 11],
        ].each do |type, value, base, expected_value|
          context "support #{type}" do
            it 'parse value' do
              expect(described_class.call(value, base: base)).to eq(expected_value)
            end
          end
        end
      end
    end

    context 'without suffix' do
      context 'integer' do
        let(:value) { '1000' }

        it 'parse value' do
          expect(described_class.call(value)).to eq(1000)
        end
      end

      context 'float' do
        let(:value) { '1.5' }

        it 'parse value' do
          expect(described_class.call(value)).to eq(2)
        end
      end
    end
  end
end
