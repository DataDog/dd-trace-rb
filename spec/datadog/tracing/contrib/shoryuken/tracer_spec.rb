require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'ddtrace'
require 'shoryuken'

RSpec.describe Datadog::Tracing::Contrib::Shoryuken::Tracer do
  let(:shoryuken_tracer) { described_class.new }
  let(:configuration_options) { {} }

  before do
    Shoryuken.worker_executor = Shoryuken::Worker::InlineExecutor

    Datadog.configure do |c|
      c.tracing.instrument :shoryuken, configuration_options
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
      stub_const(
        'TestWorker',
        Class.new do
          include Shoryuken::Worker
          shoryuken_options queue: qn
          def perform(sqs_msg, body); end
        end
      )
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

    let(:sqs_msg) { instance_double('Shoryuken::Message', message_id: message_id, attributes: attributes) }
    let(:message_id) { SecureRandom.uuid }
    let(:attributes) { {} }
    let(:body) { 'message body' }

    include_context 'Shoryuken::Worker'

    before do
      expect { call }.to_not raise_error
      expect(spans).to have(1).items
      expect(span.name).to eq(Datadog::Tracing::Contrib::Shoryuken::Ext::SPAN_JOB)
      expect(span.service).to eq(tracer.default_service)
      expect(span.get_tag(Datadog::Tracing::Contrib::Shoryuken::Ext::TAG_JOB_ID)).to eq(message_id)
      expect(span.get_tag(Datadog::Tracing::Contrib::Shoryuken::Ext::TAG_JOB_QUEUE)).to eq(queue_name)
      expect(span.get_tag(Datadog::Tracing::Contrib::Shoryuken::Ext::TAG_JOB_ATTRIBUTES)).to eq(attributes.to_s)
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('shoryuken')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('job')
      expect(span.get_tag('span.kind')).to eq('consumer')
      expect(span.get_tag('messaging.system')).to eq('amazonsqs')
    end

    it_behaves_like 'analytics for integration' do
      include_context 'Shoryuken::Worker'
      let(:body) { {} }
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Shoryuken::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Shoryuken::Ext::ENV_ANALYTICS_SAMPLE_RATE }
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
        it { expect(span.resource).to eq('TestWorker') }
      end
    end

    context 'when tag_body is true' do
      let(:configuration_options) { { tag_body: true } }

      it 'includes the body in the span' do
        expect(span.get_tag(Datadog::Tracing::Contrib::Shoryuken::Ext::TAG_JOB_BODY)).to eq(body)
      end
    end

    context 'when tag_body is false' do
      let(:configuration_options) { { tag_body: false } }

      it 'does not include the message body in the span' do
        expect(span.get_tag(Datadog::Tracing::Contrib::Shoryuken::Ext::TAG_JOB_BODY)).to be_nil
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
        # expect(span.name).to eq(Datadog::Tracing::Contrib::Shoryuken::Ext::SPAN_JOB)
        # TODO: Stub OpenStruct mock SQS message created by InlineExecutor with data
        #       https://github.com/phstc/shoryuken/blob/master/lib/shoryuken/worker/inline_executor.rb#L9
        # expect(span.get_tag(Datadog::Tracing::Contrib::Shoryuken::Ext::TAG_JOB_ID)).to eq(message_id)
        # expect(span.get_tag(Datadog::Tracing::Contrib::Shoryuken::Ext::TAG_JOB_QUEUE)).to eq(queue_name)
        # expect(span.get_tag(Datadog::Tracing::Contrib::Shoryuken::Ext::TAG_JOB_ATTRIBUTES)).to eq(attributes)
      end
    end
  end
end
