# frozen_string_literal: true

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
      let(:payload) { { job: job } }
      let(:job) { instance_double('Job', class: job_class, executor: executor, messages: messages) }
      let(:job_class) { Class.new }
      let(:executor) { instance_double('Executor', topic: topic, partition: 1) }
      let(:topic) { instance_double('Topic', consumer: 'Consumer', name: 'topic_name') }
      let(:messages) { [instance_double('Message', metadata: metadata)] }
      let(:metadata) { instance_double('Metadata', offset: 42) }

      it 'traces a consumer job' do
        Karafka.monitor.instrument(
          'worker.processed',
          payload
        )

        expect(spans).to have(1).items

        span, _push = spans

        expect(span.resource).to eq('Consumer#consume')
        expect(span.get_tag(Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT)).to eq(1)
        expect(span.get_tag(Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION)).to eq(1)
        expect(span.get_tag(Datadog::Tracing::Contrib::Karafka::Ext::TAG_OFFSET)).to eq(42)
        expect(span.get_tag(Datadog::Tracing::Contrib::Karafka::Ext::TAG_CONSUMER)).to eq('Consumer')
        expect(span.get_tag('messaging.destination')).to eq('topic_name')
        expect(span.get_tag('messaging.system')).to eq(Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM)
      end
    end
  end
end
