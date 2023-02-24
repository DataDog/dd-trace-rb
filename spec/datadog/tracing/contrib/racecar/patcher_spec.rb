require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'spec/support/thread_helpers'

# FFI::Function background native thread
ThreadHelpers.with_leaky_thread_creation(:racecar) do
  require 'racecar'
end

require 'racecar/cli'
require 'active_support'
require 'ddtrace'
RSpec.describe 'Racecar patcher' do
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :racecar, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:racecar].reset_configuration!
    example.run
    Datadog.registry[:racecar].reset_configuration!
  end

  describe 'for both single and batch message processing' do
    let(:consumer) { 'DummyConsumer' }
    let(:payload) { { consumer_class: consumer } }

    let(:span) do
      spans.find { |s| s.name == Datadog::Tracing::Contrib::Racecar::Ext::SPAN_CONSUME }
    end

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('main_loop.racecar', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.consume')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('racecar')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('consume')
          expect(span.get_tag('span.kind')).not_to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('main_loop.racecar', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.consume')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span).to have_error
          expect(span.get_tag('span.kind')).not_to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('main_loop.racecar', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Racecar::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Racecar::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('main_loop.racecar', payload) }
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

    let(:span) do
      spans.find { |s| s.name == Datadog::Tracing::Contrib::Racecar::Ext::SPAN_MESSAGE }
    end

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('process_message.racecar', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.message')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span.get_tag('kafka.partition')).to eq(partition)
          expect(span.get_tag('kafka.offset')).to eq(offset)
          expect(span.get_tag('kafka.first_offset')).to be nil
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('racecar')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('message')
          expect(span.get_tag('span.kind')).to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
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

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.message')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span.get_tag('kafka.partition')).to eq(partition)
          expect(span.get_tag('kafka.offset')).to eq(offset)
          expect(span.get_tag('kafka.first_offset')).to be nil
          expect(span).to have_error
          expect(span.get_tag('span.kind')).to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('process_message.racecar', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Racecar::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Racecar::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('process_message.racecar', payload) }
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

    let(:span) do
      spans.find { |s| s.name == Datadog::Tracing::Contrib::Racecar::Ext::SPAN_BATCH }
    end

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('process_batch.racecar', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.batch')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span.get_tag('kafka.partition')).to eq(partition)
          expect(span.get_tag('kafka.offset')).to be nil
          expect(span.get_tag('kafka.first_offset')).to eq(offset)
          expect(span.get_tag('kafka.message_count')).to eq(message_count)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('racecar')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('batch')
          expect(span.get_tag('span.kind')).to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
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

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('racecar')
          expect(span.name).to eq('racecar.batch')
          expect(span.resource).to eq(consumer)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.consumer')).to eq(consumer)
          expect(span.get_tag('kafka.partition')).to eq(partition)
          expect(span.get_tag('kafka.offset')).to be nil
          expect(span.get_tag('kafka.first_offset')).to eq(offset)
          expect(span.get_tag('kafka.message_count')).to eq(message_count)
          expect(span).to have_error
          expect(span.get_tag('span.kind')).to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('process_batch.racecar', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Racecar::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Racecar::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('process_batch.racecar', payload) }
    end
  end
end
