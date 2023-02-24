require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'ddtrace'
require 'sneakers'

class MiddlewareWorker
  include Sneakers::Worker

  from_queue 'middleware-demo', ack: false

  def work_with_params(msg, _delivery_info, _metadata)
    msg
  end
end

class FailingMiddlewareWorker
  include Sneakers::Worker

  from_queue 'failing-middleware-demo', ack: false

  def work_with_params(_msg, _delivery_info, _metadata)
    raise ZeroDivisionError, 'failed'
  end
end

RSpec.describe Datadog::Tracing::Contrib::Sneakers::Tracer do
  let(:sneakers_tracer) { described_class.new }
  let(:configuration_options) { {} }
  let(:queue) { double }
  let(:exchange) { double }

  before do
    allow(queue).to receive(:name).and_return(queue_name)
    allow(queue).to receive(:opts).and_return({})
    allow(queue).to receive(:exchange).and_return(exchange)
    Sneakers.configure(daemonize: true, log: '/tmp/sneakers.log')
    Datadog.configure do |c|
      c.tracing.instrument :sneakers, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:sneakers].reset_configuration!
    Sneakers.clear!
    example.run
    Datadog.registry[:sneakers].reset_configuration!
    Sneakers.clear!
  end

  shared_context 'Sneakers::Worker' do
    let(:worker) { MiddlewareWorker.new(queue, Concurrent::ImmediateExecutor.new) }
    let(:queue_name) { 'middleware-demo' }
  end

  describe '#call' do
    subject(:call) do
      worker.do_work(delivery_info, metadata, message, handler)
    end

    let(:delivery_info) { double }
    let(:message) { Sneakers::ContentType.deserialize('{"foo":"bar"}', 'application/json') }
    let(:handler) { Object.new }
    let(:metadata) { double }
    let(:routing_key) { 'something' }
    let(:consumer) { double('Consumer') }

    include_context 'Sneakers::Worker'

    before do
      allow(delivery_info).to receive(:routing_key).and_return(routing_key)
      allow(delivery_info).to receive(:consumer).and_return(consumer)
      allow(consumer).to receive(:queue).and_return(queue)
      allow(metadata).to receive(:[]).with(:content_type).and_return('application/json')
    end

    it do
      expect { call }.to_not raise_error
      expect(spans).to have(1).items
      expect(span.service).to eq(tracer.default_service)
      expect(span.resource).to eq('MiddlewareWorker')
      expect(span.name).to eq(Datadog::Tracing::Contrib::Sneakers::Ext::SPAN_JOB)
      expect(span.get_tag(Datadog::Tracing::Contrib::Sneakers::Ext::TAG_JOB_ROUTING_KEY)).to eq(routing_key)
      expect(span.get_tag(Datadog::Tracing::Contrib::Sneakers::Ext::TAG_JOB_QUEUE)).to eq(queue_name)
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sneakers')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('job')
      expect(span.get_tag('span.kind')).to eq('consumer')
      expect(span.get_tag('messaging.system')).to eq('rabbitmq')
      expect(span.get_tag('messaging.rabbitmq.routing_key')).to eq('something')
    end

    context 'when the tag_body is true' do
      let(:configuration_options) { super().merge(tag_body: true) }

      it 'sends to body in the trace' do
        call
        expect(span.get_tag(Datadog::Tracing::Contrib::Sneakers::Ext::TAG_JOB_BODY)).to eq('{"foo":"bar"}')
      end
    end

    context 'when the tag_body is false' do
      let(:configuration_options) { super().merge(tag_body: false) }

      it 'sends to body in the trace' do
        call
        expect(span.get_tag(Datadog::Tracing::Contrib::Sneakers::Ext::TAG_JOB_BODY)).to be_nil
      end
    end

    it_behaves_like 'analytics for integration' do
      include_context 'Sneakers::Worker'
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Sneakers::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Sneakers::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      before { call }
    end

    it_behaves_like 'measured span for integration', true do
      include_context 'Sneakers::Worker'
      before { call }
    end

    context 'with custom error handler' do
      let(:configuration_options) { super().merge(error_handler: error_handler) }
      let(:error_handler) { proc { @error_handler_called = true } }

      let(:worker) { FailingMiddlewareWorker.new(queue, Concurrent::ImmediateExecutor.new) }
      let(:queue_name) { 'failing-middleware-demo' }

      it 'uses custom error handler' do
        call
        expect(@error_handler_called).to be_truthy
      end
    end
  end
end
