require 'spec_helper'

require 'racecar'
require 'racecar/cli'
require 'active_support'
require 'ddtrace'
RSpec.describe 'Racecar patcher' do
  let(:tracer) { get_test_tracer }

  def all_spans
    tracer.writer.spans(:keep)
  end

  before(:each) do
    Datadog.configure do |c|
      c.use :racecar, tracer: tracer
    end
  end

  describe 'for single message processing' do
    let(:topic) { 'dd_trace_test_dummy' }
    let(:consumer) { 'DummyConsumer' }
    let(:partition) { 1 }
    let(:offset) { 2 }
    let(:payload) do
      {
        consumer_class: consumer,
        topic: topic,
        partition: partition,
        offset: offset
      }
    end

    let(:racecar_span) do
      all_spans.select { |s| s.name == Datadog::Contrib::Racecar::Ext::SPAN_MESSAGE }.first
    end

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('process_message.racecar', payload)

        racecar_span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.message')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span.get_tag('kafka.partition')).to eq(partition.to_s)
          expect(span.get_tag('kafka.offset')).to eq(offset.to_s)
          expect(span.get_tag('kafka.first_offset')).to be nil
          expect(span.status).to_not eq(Datadog::Ext::Errors::STATUS)
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('process_message.racecar', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        racecar_span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.message')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span.get_tag('kafka.partition')).to eq(partition.to_s)
          expect(span.get_tag('kafka.offset')).to eq(offset.to_s)
          expect(span.get_tag('kafka.first_offset')).to be nil
          expect(span.status).to eq(Datadog::Ext::Errors::STATUS)
        end
      end
    end
  end

  describe 'for batch message processing' do
    let(:topic) { 'dd_trace_test_dummy_batch' }
    let(:consumer) { 'DummyBatchConsumer' }
    let(:partition) { 1 }
    let(:offset) { 2 }
    let(:message_count) { 5 }
    let(:payload) do
      {
        consumer_class: consumer,
        topic: topic,
        partition: partition,
        message_count: message_count,
        first_offset: offset
      }
    end

    let(:racecar_span) do
      all_spans.select { |s| s.name == Datadog::Contrib::Racecar::Ext::SPAN_BATCH }.first
    end

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('process_batch.racecar', payload)

        racecar_span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.batch')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span.get_tag('kafka.partition')).to eq(partition.to_s)
          expect(span.get_tag('kafka.offset')).to be nil
          expect(span.get_tag('kafka.first_offset')).to eq(offset.to_s)
          expect(span.get_tag('kafka.message_count')).to eq(message_count.to_s)
          expect(span.status).to_not eq(Datadog::Ext::Errors::STATUS)
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        begin
          ActiveSupport::Notifications.instrument('process_batch.racecar', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        racecar_span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.batch')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span.get_tag('kafka.partition')).to eq(partition.to_s)
          expect(span.get_tag('kafka.offset')).to be nil
          expect(span.get_tag('kafka.first_offset')).to eq(offset.to_s)
          expect(span.get_tag('kafka.message_count')).to eq(message_count.to_s)
          expect(span.status).to eq(Datadog::Ext::Errors::STATUS)
        end
      end
    end
  end
end
