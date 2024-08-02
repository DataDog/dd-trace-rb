# frozen_string_literal: true

require 'datadog/tracing/contrib/aws/service/sns'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::SNS do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:sns) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with topic_arn provided' do
    let(:topic_arn) { 'arn:aws:sns:us-west-2:123456789012:my-topic-name' }
    let(:params) { { topic_arn: topic_arn } }

    it 'sets the topic_name and aws_account based on the topic_arn' do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, '123456789012')
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, 'my-topic-name')
    end
  end

  context 'with name provided' do
    let(:params) { { name: 'my-topic-name' } }

    it 'sets the topic_name based on the provided name' do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, 'my-topic-name')
    end
  end

  context 'with neither topic_arn nor name provided' do
    it 'sets the topic_name to nil' do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, nil)
    end
  end

  shared_examples 'injects attribute propagation' do
    subject(:inject_propagation) { service.process(config, trace, context) }

    let(:config) { { propagation: true } }
    let(:trace) { Datadog::Tracing::TraceOperation.new(id: trace_id, parent_span_id: span_id) }
    let(:context) { instance_double('Context', params: params) }
    let(:params) { {} }
    let(:trace_id) { 1 }
    let(:span_id) { 2 }

    before { Datadog.configure { |c| c.tracing.instrument :aws } }

    context 'without preexisting message attributes' do
      it 'adds a propagation attribute' do
        inject_propagation
        expect(params[:message_attributes]).to eq(
          '_datadog' => {
            binary_value:
              '{"x-datadog-trace-id":"1","x-datadog-parent-id":"2",' \
              '"traceparent":"00-00000000000000000000000000000001-0000000000000002-00",' \
              '"tracestate":"dd=p:0000000000000002"}',
            data_type: 'Binary'
          }
        )
      end
    end

    context 'with existing message attributes' do
      let(:params) { { message_attributes: message_attributes } }
      let(:message_attributes) { { 'existing' => { data_type: 'String', string_value: 'value' } } }

      it 'adds a propagation attribute' do
        expect { inject_propagation }.to change { message_attributes.keys }.from(['existing']).to(['existing', '_datadog'])
      end
    end

    context 'with 10 message attributes already set' do
      let(:params) { { message_attributes: message_attributes } }
      let(:message_attributes) do
        Array.new(10) do |i|
          ["attr#{i}", { data_type: 'Number', string_value: i }]
        end.to_h
      end

      it 'does not add a propagation attribute' do
        expect { inject_propagation }.to_not(change { params })
      end
    end

    context 'disabled' do
      let(:config) { { propagation: false } }

      it 'does not add a propagation attribute' do
        expect { inject_propagation }.to_not(change { params })
      end
    end
  end

  it_behaves_like 'injects attribute propagation' do
    let(:service) { sns }
  end
end
