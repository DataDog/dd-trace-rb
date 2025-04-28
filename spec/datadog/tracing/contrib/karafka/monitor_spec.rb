# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'

require 'karafka'
require 'datadog'

RSpec.describe 'Karafka monitor' do
  before do
    Datadog.configure do |c|
      c.tracing.instrument :karafka, { distributed_tracing: true }
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
        Karafka.monitor.instrument('worker.completed')

        # NOTE: This helper doesn't workt with `change` matcher well.
        expect(traces).to have(0).items
        expect(spans).to have(0).items
      end
    end

    context 'when the event is traceable' do
      let(:job) do
        instance_double(Karafka::Processing::Jobs::Consume, class: Class.new, executor: executor, messages: messages)
      end
      let(:executor) { instance_double(Karafka::Processing::Executor, topic: topic, partition: 1) }
      let(:topic) { instance_double(Karafka::Routing::Topic, consumer: 'Consumer', name: 'topic_name') }
      let(:messages) { [instance_double(Karafka::Messages::Messages, metadata: metadata)] }
      let(:metadata) { instance_double(Karafka::Messages::Metadata, offset: 42) }

      it 'traces a consumer job' do
        Karafka.monitor.instrument('worker.processed', { job: job })

        expect(traces).to have(1).item
        expect(spans).to have(1).item

        expect(spans[0].resource).to eq('Consumer#consume')
        expect(spans[0].tags).to include(
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 1,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION => 1,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_OFFSET => 42,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_CONSUMER => 'Consumer',
          'messaging.destination' => 'topic_name',
          'messaging.system' => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM
        )
      end
    end
  end
end
