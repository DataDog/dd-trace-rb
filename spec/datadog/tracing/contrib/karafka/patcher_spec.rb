require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'karafka'
require 'datadog'

RSpec.describe 'Karafka patcher' do
  let(:configuration_options) { {distributed_tracing: true} }
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
      metadata = ::Karafka::Messages::Metadata.new
      metadata['offset'] = 412
      raw_payload = rand.to_s

      message = ::Karafka::Messages::Message.new(raw_payload, metadata)
      allow(message).to receive(:timestamp).and_return(Time.now)
      allow(message).to receive(:topic).and_return('topic_a')

      topic = ::Karafka::Routing::Topic.new('topic_a', double(id: 0))

      messages = ::Karafka::Messages::Builders::Messages.call([message], topic, 0, Time.now)

      expect(messages).to all(be_a(::Karafka::Messages::Message))

      expect(spans).to have(1).items
      expect(span).to_not be nil
      expect(span.get_tag('kafka.offset')).to eq 412
      expect(span.get_tag('messaging.destination')).to eq 'topic_a'
      expect(span.get_tag('messaging.system')).to eq 'kafka'
      expect(span).to_not have_error
      expect(span.resource).to eq 'topic_a'
    end

    context 'when the message has tracing headers' do
      let(:message) do
        headers = {}
        producer_trace = nil
        producer_span = nil
        Datadog::Tracing.trace('producer') do |span, trace|
          producer_span = span
          producer_trace = trace
          Datadog::Tracing::Contrib::Karafka.inject(trace.to_digest, headers)
        end
        metadata = ::Karafka::Messages::Metadata.new
        metadata['offset'] = 412
        metadata[headers_accessor] = headers
        raw_payload = rand.to_s

        message = ::Karafka::Messages::Message.new(raw_payload, metadata)
        allow(message).to receive(:timestamp).and_return(Time.now)
        allow(message).to receive(:topic).and_return('topic_a')
        message
      end
      let(:headers_accessor) do
        ::Karafka::Messages::Metadata.members.include?(:raw_headers) ? 'raw_headers' : 'headers'
      end

      context 'when distributed tracing is enabled' do
        it 'continues the span that produced the message' do
          producer_trace_digest = Datadog::Tracing::Contrib::Karafka.extract(message.metadata[headers_accessor])

          consumer_span = nil
          consumer_trace = nil

          Datadog::Tracing.trace('consumer') do
            consumer_span = Datadog::Tracing.active_span
            consumer_trace = Datadog::Tracing.active_trace

            topic = ::Karafka::Routing::Topic.new('topic_a', double(id: 0))
            messages = ::Karafka::Messages::Builders::Messages.call([message], topic, 0, Time.now)
            expect(messages).to all(be_a(::Karafka::Messages::Message))

            # assert that the current trace re-set to the original trace after iterating the messages
            expect(Datadog::Tracing.active_trace).to eq(consumer_trace)
            expect(Datadog::Tracing.active_span).to eq(consumer_span)
          end

          expect(spans).to have(3).items

          # assert that the message span is a continuation of the producer span
          expect(span.parent_id).to eq producer_trace_digest.span_id
          expect(span.trace_id).to eq producer_trace_digest.trace_id

          expect(span.links.map { |l| [l.trace_id, l.span_id] }).to contain_exactly(
            [consumer_trace.id, consumer_span.id]
          )
          expect(consumer_span.links.map { |l| [l.trace_id, l.span_id] }).to contain_exactly(
            [span.trace_id, span.id]
          )
        end
      end

      context 'when distributed tracing is not enabled' do
        let(:configuration_options) { { distributed_tracing: false } }

        it 'does not continue the span that produced the message' do
          consumer_span = nil
          consumer_trace = nil

          Datadog::Tracing.trace('consumer') do
            consumer_span = Datadog::Tracing.active_span
            consumer_trace = Datadog::Tracing.active_trace

            topic = ::Karafka::Routing::Topic.new('topic_a', double(id: 0))
            messages = ::Karafka::Messages::Builders::Messages.call([message], topic, 0, Time.now)
            expect(messages).to all(be_a(::Karafka::Messages::Message))

            # assert that the current trace re-set to the original trace after iterating the messages
            expect(Datadog::Tracing.active_trace).to eq(consumer_trace)
            expect(Datadog::Tracing.active_span).to eq(consumer_span)
          end

          expect(spans).to have(3).items

          # assert that the message span is not continuation of the producer span
          expect(span.parent_id).to eq(consumer_span.id)
          expect(span.trace_id).to eq(consumer_trace.id)

          expect(span.links).to be_empty
          expect(consumer_span.links).to be_empty
        end
      end
    end
  end

  describe 'worker.processed' do
    let(:span_name) { Datadog::Tracing::Contrib::Karafka::Ext::SPAN_WORKER_PROCESS }

    it 'is expected to send a span' do
      metadata = ::Karafka::Messages::Metadata.new
      metadata['offset'] = 412
      raw_payload = rand.to_s

      message = ::Karafka::Messages::Message.new(raw_payload, metadata)
      job = double(executor: double(topic: double(name: 'topic_a', consumer: 'ABC'), partition: 0), messages: [message])

      Karafka.monitor.instrument('worker.processed', {job: job}) do
        # Noop
      end

      expect(spans).to have(1).items
      expect(span).to_not be nil
      expect(span.get_tag('kafka.offset')).to eq 412
      expect(span.get_tag('kafka.partition')).to eq 0
      expect(span.get_tag('kafka.message_count')).to eq 1
      expect(span.get_tag('messaging.destination')).to eq 'topic_a'
      expect(span.get_tag('messaging.system')).to eq 'kafka'
      expect(span.resource).to eq 'ABC#consume'
    end
  end
end
