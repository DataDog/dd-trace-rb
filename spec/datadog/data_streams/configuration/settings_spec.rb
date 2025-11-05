require 'spec_helper'

RSpec.describe Datadog::DataStreams::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe 'data_streams' do
    describe '#enabled' do
      subject(:enabled) { settings.data_streams.enabled }

      context 'when DD_DATA_STREAMS_ENABLED' do
        around do |example|
          ClimateControl.modify('DD_DATA_STREAMS_ENABLED' => data_streams_enabled) do
            example.run
          end
        end

        context 'is not defined' do
          let(:data_streams_enabled) { nil }

          it { is_expected.to eq false }
        end

        context 'is defined as true' do
          let(:data_streams_enabled) { 'true' }

          it { is_expected.to eq true }
        end

        context 'is defined as false' do
          let(:data_streams_enabled) { 'false' }

          it { is_expected.to eq false }
        end
      end
    end

    describe '#enabled=' do
      subject(:set_data_streams_enabled) { settings.data_streams.enabled = data_streams_enabled }

      [true, false].each do |value|
        context "when given #{value}" do
          let(:data_streams_enabled) { value }

          before { set_data_streams_enabled }

          it { expect(settings.data_streams.enabled).to eq(value) }
        end
      end
    end

    describe '#interval' do
      subject(:interval) { settings.data_streams.interval }

      context 'when _DD_TRACE_STATS_WRITER_INTERVAL' do
        around do |example|
          ClimateControl.modify('_DD_TRACE_STATS_WRITER_INTERVAL' => data_streams_interval) do
            example.run
          end
        end

        context 'is not defined' do
          let(:data_streams_interval) { nil }

          it { is_expected.to eq 10.0 }
        end

        context 'is defined' do
          let(:data_streams_interval) { '5.0' }

          it { is_expected.to eq 5.0 }
        end

        context 'is defined as an integer' do
          let(:data_streams_interval) { '20' }

          it { is_expected.to eq 20.0 }
        end
      end
    end

    describe '#interval=' do
      subject(:set_data_streams_interval) { settings.data_streams.interval = data_streams_interval }

      context 'when given a float value' do
        let(:data_streams_interval) { 15.5 }

        before { set_data_streams_interval }

        it { expect(settings.data_streams.interval).to eq(15.5) }
      end

      context 'when given an integer value' do
        let(:data_streams_interval) { 30 }

        before { set_data_streams_interval }

        it { expect(settings.data_streams.interval).to eq(30.0) }
      end
    end
  end
end
