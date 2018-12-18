require 'spec_helper'
require_relative 'job'

require 'ddtrace'

RSpec.describe 'Resque instrumentation' do
  include_context 'Resque job'

  let(:tracer) { get_test_tracer }
  let(:pin) { ::Resque.datadog_pin }
  let(:spans) { tracer.writer.spans }
  let(:span) { spans.first }

  let(:url) { "redis://#{host}:#{port}" }
  let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379) }

  before(:each) do
    # Setup Resque to use Redis
    ::Resque.redis = url
    ::Resque::Failure.clear

    # Patch Resque
    Datadog.configure do |c|
      c.use :resque
    end

    # Update the Resque pin with the tracer
    pin.tracer = tracer
  end

  shared_examples 'job execution tracing' do
    context 'that succeeds' do
      before(:each) { perform_job(job_class) }

      it 'is traced' do
        expect(spans).to have(1).items
        expect(Resque::Failure.count).to be(0)
        expect(span.name).to eq('resque.job')
        expect(span.resource).to eq(job_class.name)
        expect(span.span_type).to eq(Datadog::Ext::AppTypes::WORKER)
        expect(span.service).to eq('resque')
        expect(span.status).to_not eq(Datadog::Ext::Errors::STATUS)
      end
    end

    context 'that fails' do
      before(:each) do
        # Rig the job to fail
        expect(job_class).to receive(:perform) do
          raise error_class, error_message
        end

        # Perform it
        perform_job(job_class)
      end

      let(:error_class_name) { 'TestJobFailError' }
      let(:error_class) { stub_const(error_class_name, Class.new(StandardError)) }
      let(:error_message) { 'TestJob failed' }

      it 'is traced' do
        expect(spans).to have(1).items
        expect(Resque::Failure.count).to be(1)
        expect(Resque::Failure.all['error']).to eq(error_message)
        expect(span.name).to eq('resque.job')
        expect(span.resource).to eq(job_class.name)
        expect(span.span_type).to eq(Datadog::Ext::AppTypes::WORKER)
        expect(span.service).to eq('resque')
        expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq(error_message)
        expect(span.status).to eq(Datadog::Ext::Errors::STATUS)
        expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to eq(error_class_name)
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

    it_should_behave_like 'job execution tracing'

    it 'ensures worker is not using forking' do
      expect(worker.fork_per_job?).to be_falsey
    end
  end

  context 'with forking' do
    it_should_behave_like 'job execution tracing'

    context 'trace context' do
      before(:each) do
        expect(job_class).to receive(:perform) do
          expect(tracer.active_span).to be_a_kind_of(Datadog::Span)
          expect(tracer.active_span.parent_id).to eq(0)
        end

        tracer.trace('main.process') do
          perform_job(job_class)
        end
      end

      let(:main_span) { spans.first }
      let(:job_span) { spans.last }

      it 'is clean' do
        expect(spans).to have(2).items
        expect(Resque::Failure.count).to be(0)
        expect(main_span.name).to eq('main.process')
        expect(job_span.name).to eq('resque.job')
        expect(main_span.trace_id).to_not eq(job_span.trace_id)
      end
    end

    it 'ensures worker is using forking' do
      expect(worker.fork_per_job?).to be_truthy
    end
  end

  describe 'patching for workers' do
    let(:worker_class_1) { Class.new }
    let(:worker_class_2) { Class.new }

    before(:each) do
      # Remove the patch so it applies new patch
      remove_patch!(:resque)

      # Re-apply patch, to workers
      Datadog.configure do |c|
        c.use(:resque, workers: [worker_class_1, worker_class_2])
      end
    end

    it 'adds the instrumentation module' do
      expect(worker_class_1.singleton_class.included_modules).to include(Datadog::Contrib::Resque::ResqueJob)
      expect(worker_class_2.singleton_class.included_modules).to include(Datadog::Contrib::Resque::ResqueJob)
    end
  end
end
