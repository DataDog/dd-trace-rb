require 'spec_helper'
require 'support/object_helpers'

require 'datadog/tracing/span_event'

RSpec.describe Datadog::Tracing::SpanEvent do
  subject(:span_event) { described_class.new(name, attributes: attributes, time_unix_nano: time_unix_nano) }

  let(:name) { nil }
  let(:attributes) { nil }
  let(:time_unix_nano) { nil }

  describe '::new' do
    context 'by default' do
      let(:name) { 'This happened!' }

      it do
        expect(span_event.name).to eq(name)
        expect(span_event.attributes).to eq({})
        expect(span_event.time_unix_nano / 1e9).to be_within(1).of(Time.now.to_f)
      end

      context 'with invalid attributes' do
        let(:attributes) do
          {
            'int' => 1,
            'invalid_arr1' => [1, 'a'],
            'invalid_arr2' => [[1]],
            'invalid_int1' => 2 << 65,
            'invalid_int2' => -2 << 65,
            'invalid_float1' => Float::NAN,
            'invalid_float2' => Float::INFINITY,
            'string' => 'bar',
          }
        end

        it 'skips invalid values' do
          expect(Datadog.logger).to receive(:warn).with(/Attribute invalid_.*/).exactly(6).times

          expect(span_event.attributes).to eq('int' => 1, 'string' => 'bar',)
        end
      end

      context 'with attributes with non-string keys' do
        let(:attributes) { { 1 => 'val1', sym: 'val2' } }

        it 'converts keys to strings' do
          expect(span_event.attributes).to eq('1' => 'val1', 'sym' => 'val2')
        end
      end
    end

    context 'given' do
      context ':attributes' do
        let(:attributes) { { 'tag' => 'value' } }
        it { is_expected.to have_attributes(attributes: attributes) }
      end

      context ':time_unix_nano' do
        let(:time_unix_nano) { 30000 }
        it { is_expected.to have_attributes(time_unix_nano: time_unix_nano) }
      end
    end
  end

  describe '#to_hash' do
    subject(:to_hash) { span_event.to_hash }
    let(:name) { 'Another Event!' }

    context 'with required fields' do
      it { is_expected.to eq({ 'name' => name, 'time_unix_nano' => span_event.time_unix_nano }) }
    end

    context 'with timestamp' do
      let(:time_unix_nano) { 25 }
      it { is_expected.to include('time_unix_nano' => 25) }
    end

    context 'when attributes is set' do
      let(:attributes) { { 'event.name' => 'test_event', 'event.id' => 1, 'nested' => [2, 3] } }
      it { is_expected.to include('attributes' => attributes) }
    end
  end

  describe '#to_native_format' do
    subject(:to_native_format) { span_event.to_native_format }
    let(:name) { 'Another Event!' }

    context 'with required fields' do
      it { is_expected.to eq({ 'name' => name, 'time_unix_nano' => span_event.time_unix_nano }) }
    end

    context 'with timestamp' do
      let(:time_unix_nano) { 25 }
      it { is_expected.to include('time_unix_nano' => 25) }
    end

    context 'when attributes is set' do
      let(:attributes) do
        {
          'string' => 'value',
          'bool' => true,
          'int' => 1,
          'float' => 1.0,
          'string_arr' => %w[ab cd],
          'bool_arr' => [true, false],
          'int_arr' => [1, 2],
          'float_arr' => [1.0, 2.0]
        }
      end

      it do
        expect(to_native_format['attributes']).to eq(
          'string' => { type: 0, string_value: 'value' },
          'bool' => { type: 1, bool_value: true },
          'int' => { type: 2, int_value: 1 },
          'float' => { type: 3, double_value: 1.0 },
          'string_arr' => { type: 4,
                            array_value: [{ type: 0, string_value: 'ab' }, { type: 0, string_value: 'cd' }] },
          'bool_arr' => { type: 4,
                          array_value: [{ type: 1, bool_value: true }, { type: 1, bool_value: false }] },
          'int_arr' => { type: 4, array_value: [{ type: 2, int_value: 1 }, { type: 2, int_value: 2 }] },
          'float_arr' => { type: 4,
                           array_value: [{ type: 3, double_value: 1.0 }, { type: 3, double_value: 2.0 }] }
        )
      end
    end
  end
end
