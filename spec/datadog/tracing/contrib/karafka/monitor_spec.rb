require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'karafka'
require 'datadog'

RSpec.describe 'Karafka monitor' do
  subject(:monitor) { described_class.new }
  let(:configuration_options) { { distributed_tracing: true } }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :karafka, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:karafka].reset_configuration!
    example.run
    Datadog.registry[:karafka].reset_configuration!
  end

  describe '.instrument' do
    context 'when the event is not traceable' do
      it 'does not create a trace' do
        allow(Datadog::Tracing).to receive(:trace)

        Karafka.monitor.instrument('worker.completed')

        expect(Datadog::Tracing).not_to have_received(:trace)
      end
    end

    context 'when the event is traceable' do
      let(:span) { instance_double('Span', set_tag: nil) }
      let(:event_id) { 'some_event' }
      let(:payload) { { job: job } }
      let(:job) { instance_double('Job', class: job_class, executor: executor, messages: messages) }
      let(:job_class) { Class.new }
      let(:executor) { instance_double('Executor', topic: topic, partition: 1) }
      let(:topic) { instance_double('Topic', consumer: 'Consumer', name: 'topic_name') }
      let(:messages) { [instance_double('Message', metadata: metadata)] }
      let(:metadata) { instance_double('Metadata', offset: 42) }

      it 'creates a trace' do
        allow(span).to receive(:resource=)
        allow(Datadog::Tracing).to receive(:trace).and_yield(span)

        Karafka.monitor.instrument(
          'worker.processed',
          payload
        )

        expect(Datadog::Tracing).to have_received(:trace)
        expect(span).to have_received(:resource=).with('Consumer#consume')
        expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT, 1)
        expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION, 1)
        expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Karafka::Ext::TAG_OFFSET, 42)
        expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Karafka::Ext::TAG_CONSUMER, 'Consumer')
        expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Ext::Messaging::TAG_DESTINATION, 'topic_name')
        expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Ext::Messaging::TAG_SYSTEM, Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM)
      end
    end
  end
end
