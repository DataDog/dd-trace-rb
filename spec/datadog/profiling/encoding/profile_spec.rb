require 'spec_helper'

require 'datadog/profiling/flush'
require 'datadog/profiling/encoding/profile'
require 'datadog/profiling/events/stack'

RSpec.describe Datadog::Profiling::Encoding::Profile::Protobuf do
  describe '.encode' do
    subject(:encode) do
      described_class.encode(
        event_count: event_count,
        event_groups: event_groups,
        start: start_time,
        finish: finish_time
      )
    end

    let(:event_groups) { [event_group] }
    let(:event_group) { instance_double(Datadog::Profiling::EventGroup, event_class: event_class, events: events) }
    let(:event_class) { double('event class') }
    let(:events) { double('events') }
    let(:event_count) { nil }

    let(:template) { instance_double(Datadog::Profiling::Pprof::Template, debug_statistics: 'template_debug_statistics') }
    let(:profile) { instance_double(Perftools::Profiles::Profile) }
    let(:payload) { instance_double(Datadog::Profiling::Pprof::Payload) }
    let(:start_time) { Time.utc(2020) }
    let(:finish_time) { Time.utc(2021) }

    before do
      expect(Datadog::Profiling::Pprof::Template)
        .to receive(:for_event_classes)
        .with([event_class])
        .and_return(template)

      expect(template)
        .to receive(:add_events!)
        .with(event_group.event_class, event_group.events)
        .ordered

      expect(template)
        .to receive(:to_pprof)
        .with(start: start_time, finish: finish_time)
        .and_return(payload)
        .ordered

      allow(Datadog.logger).to receive(:debug)
    end

    it 'returns a pprof-encoded profile' do
      is_expected.to be payload
    end

    describe 'debug logging' do
      let(:event_count) { 42 }

      it 'debug logs profile information' do
        expect(Datadog.logger).to receive(:debug) do |&message_block|
          message = message_block.call

          expect(message).to include '2020-01-01T00:00:00Z'
          expect(message).to include '2021-01-01T00:00:00Z'
          expect(message).to include 'template_debug_statistics'
        end

        encode
      end
    end
  end
end
