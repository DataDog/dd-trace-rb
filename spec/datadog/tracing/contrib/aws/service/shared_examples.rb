require 'datadog/tracing/contrib/aws/parsed_context'

require 'aws-sdk-sqs'

RSpec.shared_examples 'injects AWS attribute propagation' do
  subject(:inject_propagation) { service.process(config, trace, context) }

  let(:config) { { propagation: true } }
  let(:trace) { Datadog::Tracing::TraceOperation.new(id: trace_id, parent_span_id: span_id) }
  let(:context) { instance_double(Datadog::Tracing::Contrib::Aws::ParsedContext, params: params, operation: operation) }
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
          data_type: data_type
        }
      )
    end
  end

  context 'with existing message attributes' do
    let(:params) { { message_attributes: message_attributes } }
    let(:message_attributes) { { 'existing' => { data_type: 'Number', string_value: 1 } } }

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

RSpec.shared_examples 'extract AWS attribute propagation' do
  subject(:extract_propagation) { service.before_span(config, context, response) }

  let(:config) { { propagation: true, parentage_style: parentage_style } }
  let(:parentage_style) { 'distributed' }
  let(:trace) do
    Datadog::Tracing::TraceOperation.new(
      id: 1,
      parent_span_id: 2,
      remote_parent: true,
      trace_state: 'unrelated=state',
      sampling_priority: 0
    )
  end
  let(:context) { instance_double(Datadog::Tracing::Contrib::Aws::ParsedContext, operation: operation) }
  let(:response) do
    result = Aws::SQS::Types::ReceiveMessageResult.new(messages: messages)
    Seahorse::Client::Response.new(data: result)
  end
  let(:messages) { [] }

  before { Datadog.configure { |c| c.tracing.instrument :aws } }

  context 'without message attributes' do
    context 'without an active trace' do
      it 'does not create trace' do
        extract_propagation
        expect(Datadog::Tracing.active_trace).to be_nil
      end
    end

    context 'with an active trace' do
      before { Datadog::Tracing.continue_trace!(trace.to_digest) }

      it 'does not change active trace' do
        extract_propagation
        expect(Datadog::Tracing.active_trace.to_digest).to eq(trace.to_digest)
      end
    end
  end

  context 'with message attributes' do
    let(:messages) { [message] }
    let(:message) { Aws::SQS::Types::Message.new(message_attributes: message_attributes) }
    let(:message_attributes) { { '_datadog' => attribute } }
    let(:attribute) do
      Aws::SQS::Types::MessageAttributeValue.new(
        string_value:
          '{"traceparent":"00-00000000000000000000000000000001-0000000000000002-00",' \
            '"tracestate":"dd=p:0000000000000002,unrelated=state"}',
        data_type: data_type
      )
    end

    context 'without an active trace' do
      it 'creates trace' do
        extract_propagation
        expect(Datadog::Tracing.active_trace.to_digest).to eq(trace.to_digest)
      end
    end

    context 'with an active trace' do
      it 'overrides the existing trace' do
        existing_trace = Datadog::Tracing.continue_trace!(nil)
        expect { extract_propagation }.to(
          change { Datadog::Tracing.active_trace.to_digest }.from(existing_trace.to_digest).to(trace.to_digest)
        )
      end
    end

    context 'with a local parentage style' do
      let(:parentage_style) { 'local' }

      it 'does not create a remote trace' do
        extract_propagation
        expect(Datadog::Tracing.active_trace).to be_nil
      end
    end

    context 'with multiple messages' do
      let(:messages) { [message, other_message] }
      let(:other_message) { Aws::SQS::Types::Message.new(message_attributes: other_message_attributes) }
      let(:other_message_attributes) { { '_datadog' => other_attribute } }
      let(:other_attribute) do
        Aws::SQS::Types::MessageAttributeValue.new(
          string_value:
            '{"traceparent":"00-00000000000000000000000000000008-0000000000000009-00",' \
              '"tracestate":"dd=p:0000000000000009,oops=not-this-one"}',
          data_type: data_type
        )
      end

      it 'extracts the first message attributes' do
        extract_propagation
        expect(Datadog::Tracing.active_trace.to_digest).to eq(trace.to_digest)
      end
    end
  end

  context 'disabled' do
    let(:config) { { propagation: false } }

    it 'does not add a propagation attribute' do
      expect { extract_propagation }.to_not(change { params })
    end
  end
end
