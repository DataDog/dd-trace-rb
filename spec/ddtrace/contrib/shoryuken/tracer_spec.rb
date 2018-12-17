require 'spec_helper'
require 'ddtrace'
require 'shoryuken'

RSpec.describe Datadog::Contrib::Shoryuken::Tracer do
  let(:tracer) { get_test_tracer }
  let(:options) { { tracer: tracer } }
  let(:spans) { tracer.writer.spans }
  let(:span) { spans.first }

  before do
    Shoryuken.worker_executor = Shoryuken::Worker::InlineExecutor

    Datadog.configure do |c|
      c.use :shoryuken, options
    end
  end

  context 'when a Shoryuken::Worker class' do
    subject(:worker_class) do
      qn = queue_name
      stub_const('TestWorker', Class.new do
        include Shoryuken::Worker
        shoryuken_options queue: qn
        def perform(sqs_msg, body); end
      end)
    end
    let(:queue_name) { 'default' }

    describe '#perform_async' do
      subject(:perform_async) { worker_class.perform_async(body) }

      let(:body) { 'test' }

      before do
        expect_any_instance_of(worker_class).to receive(:perform)
          .with(anything, body)
          .and_call_original
      end

      it do
        expect { perform_async }.to_not raise_error
        # TODO: These expectations do not work because Shoryuken doesn't run middleware in tests
        #       https://github.com/phstc/shoryuken/issues/541
        # expect(spans).to have(1).items
        # expect(span.name).to_not eq(Datadog::Contrib::Shoryuken::Ext::SPAN_JOB)
        # TODO: Stub OpenStruct mock SQS message created by InlineExecutor with data
        #       https://github.com/phstc/shoryuken/blob/master/lib/shoryuken/worker/inline_executor.rb#L9
        # expect(span.get_tag(Datadog::Contrib::Shoryuken::Ext::TAG_JOB_ID)).to eq(message_id)
        # expect(span.get_tag(Datadog::Contrib::Shoryuken::Ext::TAG_JOB_QUEUE)).to eq(queue_name)
        # expect(span.get_tag(Datadog::Contrib::Shoryuken::Ext::TAG_JOB_ATTRIBUTES)).to eq(attributes)
      end
    end
  end
end
