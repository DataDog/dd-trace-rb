LogHelpers.without_warnings do
  require 'resque'
end

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/span_operation'
require 'datadog/tracing/contrib/resque/ext'

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

RSpec.shared_context 'Resque job' do
  def perform_job(klass, *args)
    job = Resque::Job.new(queue_name, 'class' => klass, 'args' => args)
    worker.perform(job)
  end

  let(:queue_name) { :test_queue }
  let(:worker) { Resque::Worker.new(queue_name) }
  let(:job_class) do
    stub_const('TestJob', Class.new).tap do |mod|
      mod.send(:define_singleton_method, :perform) do |*args|
        # Do nothing by default.
      end
    end
  end
  let(:job_args) { nil }
end

RSpec.describe 'Resque instrumentation' do
  include_context 'Resque job'

  let(:url) { "redis://#{host}:#{port}" }
  let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379) }

  let(:configuration_options) { {} }

  before do
    # Setup Resque to use Redis
    ::Resque.redis = url
    ::Resque::Failure.clear

    # Patch Resque
    Datadog.configure do |c|
      c.tracing.instrument :resque, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:resque].reset_configuration!
    example.run
    Datadog.registry[:resque].reset_configuration!
  end

  shared_examples 'job execution tracing' do
    context 'that succeeds' do
      before { perform_job(job_class, job_args) }

      it 'is traced' do
        expect(spans).to have(1).items
        expect(Resque::Failure.count).to eq(0)
        expect(span.name).to eq('resque.job')
        expect(span.resource).to eq(job_class.name)
        expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::AppTypes::TYPE_WORKER)
        expect(span.service).to eq(tracer.default_service)
        expect(span).to_not have_error
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('resque')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('job')
        expect(span.get_tag('span.kind')).to eq('consumer')
        expect(span.get_tag('messaging.system')).to eq('resque')
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Resque::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Resque::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', true

      context 'when the job looks like Active Job' do
        let(:job_args) do
          { 'job_class' => 'UnderlyingTestJob' }
        end

        it 'sets the resource to underlying job class' do
          expect(spans).to have(1).items
          expect(Resque::Failure.count).to eq(0)
          expect(span.resource).to eq('UnderlyingTestJob')
        end
      end
    end

    context 'that fails' do
      before do
        # Rig the job to fail
        expect(job_class).to receive(:perform) do
          raise error_class, error_message
        end
      end

      let(:error_class_name) { 'TestJobFailError' }
      let(:error_class) { stub_const(error_class_name, Class.new(StandardError)) }
      let(:error_message) { 'TestJob failed' }

      it 'is traced' do
        perform_job(job_class)
        expect(spans).to have(1).items
        expect(Resque::Failure.count).to eq(1)
        expect(Resque::Failure.all['error']).to eq(error_message)
        expect(span.name).to eq('resque.job')
        expect(span.resource).to eq(job_class.name)
        expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::AppTypes::TYPE_WORKER)
        expect(span.service).to eq(tracer.default_service)
        expect(span).to have_error_message(error_message)
        expect(span).to have_error
        expect(span).to have_error_type(error_class_name)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('resque')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('job')
        expect(span.get_tag('span.kind')).to eq('consumer')
        expect(span.get_tag('messaging.system')).to eq('resque')
      end

      context 'with custom error handler' do
        let(:configuration_options) { super().merge(error_handler: error_handler) }
        let(:error_handler) { proc { @error_handler_called = true } }

        it 'uses custom error handler' do
          perform_job(job_class)
          expect(@error_handler_called).to be_truthy
        end
      end
    end
  end

  context 'without forking' do
    around do |example|
      orig_fork_per_job = ENV['FORK_PER_JOB']
      begin
        ENV['FORK_PER_JOB'] = 'false'
        example.run
      ensure
        ENV['FORK_PER_JOB'] = orig_fork_per_job
      end
    end

    let(:configuration_options) { { auto_instrument: true } }

    it_behaves_like 'job execution tracing'

    it 'ensures worker is not using forking' do
      expect(worker).not_to be_fork_per_job
    end
  end

  context 'with forking' do
    before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

    let(:configuration_options) { { auto_instrument: true } }

    it_behaves_like 'job execution tracing'

    context 'trace context' do
      before do
        expect(job_class).to receive(:perform) do
          expect(tracer.active_span).to be_a_kind_of(Datadog::Tracing::SpanOperation)
          expect(tracer.active_span.parent_id).to eq(0)
        end

        # On completion of the fork, `Datadog::Tracing.shutdown!` will be invoked.
        expect(Datadog::Tracing).to receive(:shutdown!)

        tracer.trace('main.process') do
          perform_job(job_class)
        end
      end

      let(:main_span) { spans.first }
      let(:job_span) { spans.last }

      it 'is clean' do
        expect(spans).to have(2).items
        expect(Resque::Failure.count).to eq(0)
        expect(main_span.name).to eq('main.process')
        expect(job_span.name).to eq('resque.job')
        expect(main_span.trace_id).to_not eq(job_span.trace_id)
      end
    end

    it 'ensures worker is using forking' do
      expect(worker).to be_fork_per_job
    end
  end

  describe 'with default instrumentation of all workers' do
    let(:configuration_options) { {} }

    it_behaves_like 'job execution tracing'
  end
end
