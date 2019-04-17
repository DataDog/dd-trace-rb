require 'spec_helper'

require 'ddtrace'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/distributed_headers'

RSpec.describe Datadog::DistributedHeaders do
  subject(:headers) do
    described_class.new(env)
  end
  let(:env) { {} }

  # Helper to format env header keys
  def env_header(name)
    "http-#{name}".upcase!.tr('-', '_')
  end

  describe '#origin' do
    context 'no origin header' do
      it { expect(headers.origin).to be_nil }
    end

    context 'incorrect header' do
      [
        'X-DATADOG-ORIGN', # Typo
        'DATADOG-ORIGIN',
        'X-ORIGIN',
        'ORIGIN'
      ].each do |header|
        context header do
          let(:env) { { env_header(header) => 'synthetics' } }

          it { expect(headers.origin).to be_nil }
        end
      end
    end

    context 'origin in header' do
      [
        ['', nil],
        %w[synthetics synthetics],
        %w[origin origin]
      ].each do |value, expected|
        context "set to #{value}" do
          let(:env) { { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => value } }

          it { expect(headers.origin).to eq(expected) }
        end
      end
    end
  end

  describe '#trace_id' do
    context 'no trace_id header' do
      it { expect(headers.trace_id).to be_nil }
    end

    context 'incorrect header' do
      shared_examples_for 'ignored trace ID header' do |header|
        let(:env) { { env_header(header) => '100' } }
        it { expect(headers.trace_id).to be_nil }
      end

      [
        'X-DATADOG-TRACE-ID-TYPO',
        'X-DATDOG-TRACE-ID',
        'X-TRACE-ID',
        'TRACE-ID'
      ].each do |header|
        it_behaves_like 'ignored trace ID header', header
      end
    end

    context 'trace_id in header' do
      [
        ['123', 123],
        ['0', nil],
        ['a', nil],
        ['-1', 18446744073709551615],
        ['-8809075535603237910', 9637668538106313706],
        ['ooops', nil],

        # Boundaries of what we generate
        [Datadog::Span::MAX_ID.to_s, Datadog::Span::MAX_ID],
        [(Datadog::Span::MAX_ID + 1).to_s, Datadog::Span::MAX_ID + 1],

        # Max allowed values
        [Datadog::Span::EXTERNAL_MAX_ID.to_s, Datadog::Span::EXTERNAL_MAX_ID],
        [(Datadog::Span::EXTERNAL_MAX_ID + 1).to_s, nil]
      ].each do |value, expected|
        context "set to #{value}" do
          let(:env) { { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID) => value } }

          it { expect(headers.trace_id).to eq(expected) }
        end
      end
    end
  end

  describe '#parent_id' do
    context 'no parent_id header' do
      it { expect(headers.parent_id).to be_nil }
    end

    context 'incorrect header' do
      shared_examples_for 'ignored parent ID header' do |header|
        let(:env) { { env_header(header) => '100' } }
        it { expect(headers.parent_id).to be_nil }
      end

      [
        'X-DATADOG-PARENT-ID-TYPO',
        'X-DATDOG-PARENT-ID',
        'X-PARENT-ID',
        'PARENT-ID'
      ].each do |header|
        it_behaves_like 'ignored parent ID header', header
      end
    end

    context 'parent_id in header' do
      [
        ['123', 123],
        ['0', nil],
        ['a', nil],
        ['-1', 18446744073709551615],
        ['-8809075535603237910', 9637668538106313706],
        ['ooops', nil],

        # Boundaries of what we generate
        [Datadog::Span::MAX_ID.to_s, Datadog::Span::MAX_ID],
        [(Datadog::Span::MAX_ID + 1).to_s, Datadog::Span::MAX_ID + 1],

        # Max allowed values
        [Datadog::Span::EXTERNAL_MAX_ID.to_s, Datadog::Span::EXTERNAL_MAX_ID],
        [(Datadog::Span::EXTERNAL_MAX_ID + 1).to_s, nil]
      ].each do |value, expected|
        context "set to #{value}" do
          let(:env) { { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID) => value } }

          it { expect(headers.parent_id).to eq(expected) }
        end
      end
    end
  end

  describe '#sampling_priority' do
    context 'no sampling priorityheader' do
      it { expect(headers.sampling_priority).to be_nil }
    end

    context 'incorrect header' do
      shared_examples_for 'ignored sampling priority header' do |header|
        let(:env) { { env_header(header) => '100' } }
        it { expect(headers.sampling_priority).to be_nil }
      end

      [
        'X-DATADOG-SAMPLING-PRIORITY-TYPO',
        'X-DATDOG-SAMPLING-PRIORITY',
        'X-SAMPLING-PRIORITY',
        'SAMPLING-PRIORITY'
      ].each do |header|
        it_behaves_like 'ignored sampling priority header', header
      end
    end

    context 'sampling_priority in header' do
      [
        # Allowed values
        ['-1', -1],
        ['0', 0],
        ['1', 1],
        ['2', 2],

        # Outside of bounds, but still allowed since a number
        ['-2', -2],
        ['3', 3],
        ['999', 999],

        # Not a number
        ['ooops', nil]
      ].each do |value, expected|
        context "set to #{value}" do
          let(:env) { { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY) => value } }

          it { expect(headers.sampling_priority).to eq(expected) }
        end
      end
    end
  end

  describe '#valid?' do
    context 'with headers' do
      [
        # Trace id and Parent id with no other headers - valid
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '456' },
          true
        ],

        # All acceptable values for sampling priority - valid
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '456',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => '-1' },
          true
        ],
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '456',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => '0' },
          true
        ],
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '456',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => '1' },
          true
        ],
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '456',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => '2' },
          true
        ],

        # Invalid Trace id - invalid
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => 'a',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '456',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => '0' },
          false
        ],

        # Invalid Parent id - invalid
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => 'a',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => '0' },
          false
        ],

        # Invalid sampling priority - valid
        # DEV: This is valid because sampling priority isn't required
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '456',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => 'nan' },
          true
        ],

        # Trace id and Parent id both 0 - invalid
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '0',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '0',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => '0' },
          false
        ],

        # Typos in header names - invalid
        [
          { 'X-DATADOG-TRACE-ID-TYPO' => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '456' },
          false
        ],
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            'X-DATADOG-PARENT-ID-TYPO' => '456' },
          false
        ],

        # Parent id is not required when origin is 'synthetics' - valid
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '0',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN => 'synthetics' },
          true
        ],
        # Invalid when not 'synthetics' - invalid
        [
          { Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '123',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '0',
            Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN => 'not-synthetics' },
          false
        ]
      ].each do |test_headers, expected|
        context test_headers.to_s do
          let(:env) { Hash[test_headers.map { |k, v| [env_header(k), v] }] }

          it { expect(headers.valid?).to eq(expected) }
        end
      end
    end
  end
end
