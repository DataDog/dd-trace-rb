# typed: false
require 'spec_helper'

require 'datadog/profiling/encoding/profile'
require 'datadog/profiling/events/stack'

RSpec.describe Datadog::Profiling::Encoding::Profile::Protobuf do
  describe '::encode' do
    subject(:encode) { described_class.encode(flush) }

    let(:flush) do
      instance_double(Datadog::Profiling::OldFlush, event_groups: event_groups, start: start_time, finish: finish_time)
    end
    let(:event_groups) { [event_group] }
    let(:event_group) { instance_double(Datadog::Profiling::EventGroup, event_class: event_class, events: events) }
    let(:event_class) { double('event class') }
    let(:events) { double('events') }

    let(:template) { instance_double(Datadog::Profiling::Pprof::Template) }
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
    end

    it { is_expected.to be payload }

    context 'debug logging' do
      before do
        allow(flush).to receive(:event_count).and_return(42)
      end

      let(:template) { instance_double(Datadog::Profiling::Pprof::Template, debug_statistics: 'template_debug_statistics') }

      it 'debug logs profile information' do
        expect(Datadog.logger).to receive(:debug) do |&message|
          expect(message.call).to include '2020-01-01T00:00:00Z'
          expect(message.call).to include '2021-01-01T00:00:00Z'
          expect(message.call).to include 'template_debug_statistics'
        end

        encode
      end
    end
  end
end
