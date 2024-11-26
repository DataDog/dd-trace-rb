require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'karafka'
require 'datadog'

RSpec.describe 'Karafka patcher' do
  let(:configuration_options) { {} }
  let(:client_id) { SecureRandom.uuid }
  let(:span) do
    spans.find { |s| s.name == span_name }
  end

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

  describe 'Karafka::message#consume' do
    let(:span_name) { Datadog::Tracing::Contrib::Karafka::Ext::SPAN_MESSAGE_CONSUME }

    it 'is expected to send a span' do
      metadata = ::Karafka::Messages::Metadata.new.tap do |metadata|
        metadata['offset'] = 412
      end
      raw_payload = rand.to_s

      message = Karafka::Messages::Message.new(raw_payload, metadata)
      allow(message).to receive(:timestamp).and_return(Time.now)
      allow(message).to receive(:topic).and_return('topic_a')

      topic = Karafka::Routing::Topic.new('topic_a', double(id: 0))

      messages = Karafka::Messages::Builders::Messages.call([message], topic, 0, Time.now)

      messages.each do |msg|
        expect(msg).to be_a(Karafka::Messages::Message)
      end

      expect(spans).to have(1).items
      expect(span).to_not be nil
      expect(span.get_tag('kafka.offset')).to eq 412
      expect(span.get_tag('kafka.topic')).to eq 'topic_a'
      expect(span).to_not have_error
      expect(span.resource).to eq 'topic_a'
    end
  end

  describe 'worker.processed' do
    let(:span_name) { Datadog::Tracing::Contrib::Karafka::Ext::SPAN_WORKER_PROCESS }

    it 'is expected to send a span' do
      metadata = ::Karafka::Messages::Metadata.new.tap do |metadata|
        metadata['offset'] = 412
      end
      raw_payload = rand.to_s

      message = Karafka::Messages::Message.new(raw_payload, metadata)
      job = double(executor: double(topic: double(name: 'topic_a', consumer: 'ABC'), partition: 0), messages: [message])

      Karafka.monitor.instrument('worker.processed', { job: job }) do
        # Noop
      end

      expect(spans).to have(1).items
      expect(span).to_not be nil
      expect(span.get_tag('kafka.offset')).to eq 412
      expect(span.get_tag('kafka.topic')).to eq 'topic_a'
      expect(span.get_tag('kafka.partition')).to eq 0
      expect(span.get_tag('kafka.message_count')).to eq 1
      expect(span.resource).to eq 'ABC#consume'
    end
  end
end
