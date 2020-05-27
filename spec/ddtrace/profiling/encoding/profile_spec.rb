require 'spec_helper'

require 'ddtrace/profiling/encoding/profile'
require 'ddtrace/profiling/events/stack'

RSpec.describe Datadog::Profiling::Encoding::Profile::Protobuf do
  describe '::encode' do
    subject(:encode) { described_class.encode(flushes) }

    let(:flushes) { [flush] }
    let(:flush) { instance_double(Datadog::Profiling::Flush, event_class: event_class, events: events) }
    let(:event_class) { double('event class') }
    let(:events) { double('events') }

    let(:template) { instance_double(Datadog::Profiling::Pprof::Template) }
    let(:profile) { instance_double(Perftools::Profiles::Profile) }
    let(:encoded_profile) { instance_double(String) }
    let(:encoded_data) { instance_double(String) }

    before do
      expect(Datadog::Profiling::Pprof::Template)
        .to receive(:for_event_classes)
        .with([event_class])
        .and_return(template)

      expect(template)
        .to receive(:add_events!)
        .with(flush.event_class, flush.events)

      expect(template)
        .to receive(:to_profile)
        .and_return(profile)

      expect(Perftools::Profiles::Profile)
        .to receive(:encode)
        .with(profile)
        .and_return(encoded_profile)

      expect(encoded_profile)
        .to receive(:force_encoding)
        .with('UTF-8')
        .and_return(encoded_data)
    end

    it { is_expected.to be encoded_data }
  end
end
