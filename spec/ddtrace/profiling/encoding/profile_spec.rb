require 'spec_helper'

require 'ddtrace/profiling/encoding/profile'
require 'ddtrace/profiling/events/stack'

RSpec.describe Datadog::Profiling::Encoding::Profile::Protobuf do
  describe '::encode' do
    subject(:encode) { described_class.encode(flush) }

    let(:flush) { instance_double(Datadog::Profiling::Flush, event_groups: event_groups) }
    let(:event_groups) { [event_group] }
    let(:event_group) { instance_double(Datadog::Profiling::EventGroup, event_class: event_class, events: events) }
    let(:event_class) { double('event class') }
    let(:events) { double('events') }

    let(:template) { instance_double(Datadog::Profiling::Pprof::Template) }
    let(:profile) { instance_double(Perftools::Profiles::Profile) }
    let(:payload) { instance_double(Datadog::Profiling::Pprof::Payload) }

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
        .and_return(payload)
        .ordered
    end

    it { is_expected.to be payload }
  end
end
