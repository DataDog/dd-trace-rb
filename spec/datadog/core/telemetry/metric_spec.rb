require 'spec_helper'

require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Metric do
  let(:now) { 123123 }
  before { allow(Time).to receive(:now).and_return(now, now + 1, now + 2, now + 3) }

  describe '.metric_id' do
    subject(:metric_id) { described_class.metric_id(type, name, tags) }

    let(:type) { 'type' }
    let(:name) { 'name' }
    let(:tags) { ['tag1:val1', 'tag2:val2'] }

    it { is_expected.to eq('type::name::tag1:val1,tag2:val2') }
  end

  describe Datadog::Core::Telemetry::Metric::Count do
    subject(:metric) { described_class.new(name, tags: tags) }

    let(:name) { 'metric_name' }
    let(:tags) { { tag1: 'val1', tag2: 'val2' } }

    it do
      is_expected.to have_attributes(
        name: name,
        tags: ['tag1:val1', 'tag2:val2'],
        interval: nil,
        common: true,
        values: []
      )
    end

    describe '#type' do
      subject(:type) { metric.type }

      it { is_expected.to eq('count') }
    end

    describe '#inc' do
      subject(:inc) { metric.inc(value) }

      let(:value) { 5 }

      it 'tracks the value' do
        expect { inc }.to change { metric.values }.from([]).to([[now, value]])
      end

      context 'incrementing again' do
        it 'adds the value to the previous one and updates timestamp' do
          metric.inc(value)
          expect { inc }.to change { metric.values }.from([[now, value]]).to([[now + 1, value + value]])
        end
      end
    end

    describe '#dec' do
      subject(:dec) { metric.dec(value) }

      let(:value) { 5 }

      it 'tracks the value' do
        expect { dec }.to change { metric.values }.from([]).to([[now, -value]])
      end
    end

    describe '#to_h' do
      subject(:to_h) { metric.to_h }
      let(:value) { 2 }

      before do
        metric.inc(value)
      end

      it do
        is_expected.to eq(
          metric: name,
          points: [[now, 2]],
          type: 'count',
          tags: ['tag1:val1', 'tag2:val2'],
          common: true
        )
      end
    end
  end

  describe Datadog::Core::Telemetry::Metric::Gauge do
    subject(:metric) { described_class.new(name, tags: tags, interval: interval) }

    let(:name) { 'metric_name' }
    let(:tags) { { tag1: 'val1', tag2: 'val2' } }
    let(:interval) { 10 }

    it do
      is_expected.to have_attributes(
        name: name,
        tags: ['tag1:val1', 'tag2:val2'],
        interval: interval,
        common: true,
        values: []
      )
    end

    describe '#type' do
      subject(:type) { metric.type }

      it { is_expected.to eq('gauge') }
    end

    describe '#track' do
      subject(:track) { metric.track(value) }

      let(:value) { 5 }

      it 'tracks the value' do
        expect { track }.to change { metric.values }.from([]).to([[now, value]])
      end

      context 'tracking again' do
        it 'updates the value and timestamp' do
          metric.track(value + 1)
          expect { track }.to change { metric.values }.from([[now, value + 1]]).to([[now + 1, value]])
        end
      end
    end

    describe '#to_h' do
      subject(:to_h) { metric.to_h }
      let(:value) { 2 }

      before do
        metric.track(value)
      end

      it do
        is_expected.to eq(
          metric: name,
          points: [[now, 2]],
          type: 'gauge',
          tags: ['tag1:val1', 'tag2:val2'],
          common: true,
          interval: interval
        )
      end
    end
  end

  describe Datadog::Core::Telemetry::Metric::Rate do
    subject(:metric) { described_class.new(name, tags: tags, interval: interval) }

    let(:name) { 'metric_name' }
    let(:tags) { { tag1: 'val1', tag2: 'val2' } }
    let(:interval) { 10 }

    it do
      is_expected.to have_attributes(
        name: name,
        tags: ['tag1:val1', 'tag2:val2'],
        interval: interval,
        common: true,
        values: []
      )
    end

    describe '#type' do
      subject(:type) { metric.type }

      it { is_expected.to eq('rate') }
    end

    describe '#track' do
      subject(:track) { metric.track(value) }

      let(:value) { 5 }

      it 'tracks the rate value' do
        expect { track }.to change { metric.values }.from([]).to([[now, value.to_f / interval]])
      end

      context 'tracking again' do
        it 'updates the value and timestamp' do
          metric.track(value)
          expect { track }.to change { metric.values }
            .from([[now, value.to_f / interval]])
            .to([[now + 1, (value + value).to_f / interval]])
        end
      end

      context 'interval is nil' do
        let(:interval) { nil }

        it 'sets rate to zero' do
          expect { track }.to change { metric.values }.from([]).to([[now, 0.0]])
        end
      end
    end

    describe '#to_h' do
      subject(:to_h) { metric.to_h }
      let(:value) { 2 }

      before do
        metric.track(value)
      end

      it do
        is_expected.to eq(
          metric: name,
          points: [[now, 0.2]],
          type: 'rate',
          tags: ['tag1:val1', 'tag2:val2'],
          common: true,
          interval: 10
        )
      end
    end
  end

  describe Datadog::Core::Telemetry::Metric::Distribution do
    subject(:metric) { described_class.new(name, tags: tags) }

    let(:name) { 'metric_name' }
    let(:tags) { { tag1: 'val1', tag2: 'val2' } }

    it do
      is_expected.to have_attributes(
        name: name,
        tags: ['tag1:val1', 'tag2:val2'],
        interval: nil,
        common: true,
        values: []
      )
    end

    describe '#type' do
      subject(:type) { metric.type }

      it { is_expected.to eq('distributions') }
    end

    describe '#track' do
      subject(:track) { metric.track(value) }

      let(:value) { 5 }

      it 'tracks the value' do
        expect { track }.to change { metric.values }.from([]).to([value])
      end

      context 'tracking again' do
        it 'adds the value to the previous ones' do
          metric.track(value)
          expect { track }.to change { metric.values }.from([value]).to([value, value])
        end
      end
    end

    describe '#to_h' do
      subject(:to_h) { metric.to_h }
      let(:value) { 2 }

      before do
        metric.track(value)
      end

      it do
        is_expected.to eq(
          metric: name,
          points: [2],
          tags: ['tag1:val1', 'tag2:val2'],
          common: true
        )
      end
    end
  end
end
