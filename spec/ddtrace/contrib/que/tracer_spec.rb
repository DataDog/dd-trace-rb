require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace'
require 'que'

class MiddlewareWorker
  include Que::Worker

  from_queue 'middleware-demo', ack: false

  def work_with_params(msg, delivery_info, metadata)
    msg
  end
end

RSpec.describe Datadog::Contrib::Que::Tracer do
  let(:que_tracer) { described_class.new }
  let(:configuration_options) { {} }
  let(:queue) { double() }
  let(:exchange) { double() }

  before do
    allow(queue).to receive(:name).and_return(queue_name)
    allow(queue).to receive(:opts).and_return({})
    allow(queue).to receive(:exchange).and_return(exchange)
    Que.configure(daemonize: true, log: '/tmp/que.log')
    Datadog.configure do |c|
      c.use :que, configuration_options
    end
  end

  # Reset before and after each example; don't allow global state to linger.
  around do |example|
    Datadog.registry[:que].reset_configuration!
    Que.clear!

    example.run

    Datadog.registry[:que].reset_configuration!
    Que.clear!
  end

  shared_context 'Que::Worker' do
    let(:worker) { MiddlewareWorker.new(queue, Concurrent::ImmediateExecutor.new) }
    let(:queue_name) { 'middleware-demo' }
  end

  describe '#call' do
    subject(:call) do
      worker.do_work(delivery_info, metadata, message, handler)
    end

    let(:delivery_info) { double() }
    let(:message) { Que::ContentType.deserialize('{"foo":"bar"}', 'application/json') }
    let(:handler) { Object.new }
    let(:metadata) { double() }
    let(:routing_key) { 'something' }
    let(:consumer) { double('Consumer') }

    include_context 'Que::Worker'

    before do
      allow(delivery_info).to receive(:routing_key).and_return(routing_key)
      allow(delivery_info).to receive(:consumer).and_return(consumer)
      allow(consumer).to receive(:queue).and_return(queue)
      allow(metadata).to receive(:[]).with(:content_type).and_return('application/json')
      expect { call }.to_not raise_error
      expect(spans).to have(1).items
      expect(span.resource).to eq('MiddlewareWorker')
      expect(span.name).to eq(Datadog::Contrib::Que::Ext::SPAN_JOB)
      expect(span.get_tag(Datadog::Contrib::Que::Ext::TAG_JOB_ROUTING_KEY)).to eq(routing_key)
      expect(span.get_tag(Datadog::Contrib::Que::Ext::TAG_JOB_QUEUE)).to eq(queue_name)
    end

    context 'when the tag_body is true' do
      let(:configuration_options) { super().merge(tag_body: true) }

      it 'sends to body in the trace' do
        expect(span.get_tag(Datadog::Contrib::Que::Ext::TAG_JOB_BODY)).to eq('{"foo":"bar"}')
      end
    end

    context 'when the tag_body is false' do
      let(:configuration_options) { super().merge(tag_body: false) }

      it 'sends to body in the trace' do
        expect(span.get_tag(Datadog::Contrib::Que::Ext::TAG_JOB_BODY)).to be_nil
      end
    end

    it_behaves_like 'analytics for integration' do
      include_context 'Que::Worker'
      let(:analytics_enabled_var) { Datadog::Contrib::Que::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::Que::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      before { call }
    end

    it_behaves_like 'measured span for integration', true do
      include_context 'Que::Worker'
      before { call }
    end
  end
end
