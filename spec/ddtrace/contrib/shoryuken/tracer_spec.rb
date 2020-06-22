require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'ddtrace'
require 'shoryuken'

RSpec.describe Datadog::Contrib::Shoryuken::Tracer do
  let(:shoryuken_tracer) { described_class.new }
  let(:configuration_options) { {} }

  before do
    Shoryuken.worker_executor = Shoryuken::Worker::InlineExecutor

    Datadog.configure do |c|
      c.use :shoryuken, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:shoryuken].reset_configuration!
    example.run
    Datadog.registry[:shoryuken].reset_configuration!
  end

  shared_context 'Shoryuken::Worker' do
    let(:worker_class) do
      qn = queue_name
      stub_const('TestWorker', Class.new do
        include Shoryuken::Worker
        shoryuken_options queue: qn
        def perform(sqs_msg, body); end
      end)
    end
    let(:worker) { worker_class.new }
    let(:queue_name) { 'default' }
  end

  describe '#call' do
    subject(:call) do
      shoryuken_tracer.call(worker, queue_name, sqs_msg, body) do
        worker.perform(sqs_msg, body)
      end
    end

    # TODO: Convert this to an instance double, to verify stub.
    let(:sqs_msg) { double('sqs_msg', message_id: message_id, attributes: attributes) }
    let(:message_id) { SecureRandom.uuid }
    let(:attributes) { {} }

    include_context 'Shoryuken::Worker'

    before do
      expect { call }.to_not raise_error
      expect(spans).to have(1).items
      expect(span.name).to eq(Datadog::Contrib::Shoryuken::Ext::SPAN_JOB)
      expect(span.get_tag(Datadog::Contrib::Shoryuken::Ext::TAG_JOB_ID)).to eq(message_id)
      expect(span.get_tag(Datadog::Contrib::Shoryuken::Ext::TAG_JOB_QUEUE)).to eq(queue_name)
      expect(span.get_tag(Datadog::Contrib::Shoryuken::Ext::TAG_JOB_ATTRIBUTES)).to eq(attributes.to_s)
    end

    it_behaves_like 'analytics for integration' do
      include_context 'Shoryuken::Worker'
      let(:body) { {} }
      let(:analytics_enabled_var) { Datadog::Contrib::Shoryuken::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::Shoryuken::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      before { call }
    end

    it_behaves_like 'measured span for integration', true do
      include_context 'Shoryuken::Worker'
      let(:body) { {} }
      before { call }
    end

    context 'with a body' do
      context 'that is a Hash' do
        context 'that contains \'job_class\'' do
          let(:body) { { 'job_class' => job_class } }
          let(:job_class) { 'MyJob' }
          it { expect(span.resource).to eq(job_class) }
        end

        context 'that does not contain \'job_class\'' do
          let(:body) { {} }
          it { expect(span.resource).to eq('TestWorker') }
        end
      end

      context 'that is a String' do
        let(:body) { 'my body' }
        it { expect(span.resource).to eq('TestWorker') }
      end
    end
  end

  context 'when a Shoryuken::Worker class' do
    include_context 'Shoryuken::Worker'

    describe '#perform_async' do
      subject(:perform_async) { worker_class.perform_async(body) }

      let(:body) { 'test' }

      before do
        expect_any_instance_of(worker_class).to receive(:perform)
          .with(anything, body)
          .and_call_original
      end

      # TODO: These expectations do not work because Shoryuken doesn't run middleware in tests
      #       https://github.com/phstc/shoryuken/issues/541
      # it_behaves_like 'analytics for integration' do
      #   before { perform_async }
      # end

      it do
        expect { perform_async }.to_not raise_error
        # TODO: These expectations do not work because Shoryuken doesn't run middleware in tests
        #       https://github.com/phstc/shoryuken/issues/541
        # expect(spans).to have(1).items
        # expect(span.name).to eq(Datadog::Contrib::Shoryuken::Ext::SPAN_JOB)
        # TODO: Stub OpenStruct mock SQS message created by InlineExecutor with data
        #       https://github.com/phstc/shoryuken/blob/master/lib/shoryuken/worker/inline_executor.rb#L9
        # expect(span.get_tag(Datadog::Contrib::Shoryuken::Ext::TAG_JOB_ID)).to eq(message_id)
        # expect(span.get_tag(Datadog::Contrib::Shoryuken::Ext::TAG_JOB_QUEUE)).to eq(queue_name)
        # expect(span.get_tag(Datadog::Contrib::Shoryuken::Ext::TAG_JOB_ATTRIBUTES)).to eq(attributes)
      end
    end
  end
end
