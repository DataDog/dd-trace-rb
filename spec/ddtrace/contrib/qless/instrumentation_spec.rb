require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/contrib/qless/integration'
require_relative 'support/job'

require 'ddtrace'

RSpec.describe 'Qless instrumentation' do
  include_context 'Qless job'

  let(:configuration_options) { {} }

  before(:each) do
    delete_all_redis_keys

    # Patch Qless
    Datadog.configure do |c|
      c.use :qless, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:qless].reset_configuration!
    example.run
    Datadog.registry[:qless].reset_configuration!
  end

  shared_examples 'job execution tracing' do
    context 'that succeeds' do
      before(:each) do
        perform_job(job_class, job_args)
      end

      it 'is traced' do
        expect(spans).to have(1).items
        expect(failed_jobs.count).to eq(0)
        expect(span.name).to eq('qless.job')
        expect(span.resource).to eq(job_class.name)
        expect(span.span_type).to eq(Datadog::Ext::AppTypes::WORKER)
        expect(span.service).to eq('qless')
        expect(span).to_not have_error
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::Qless::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::Qless::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', true
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
        expect(failed_jobs.count).to eq(1)
        expect(failed_jobs).to eq('TestJob:TestJobFailError' => 1)
        expect(span.name).to eq('qless.job')
        expect(span.resource).to eq(job_class.name)
        expect(span.span_type).to eq(Datadog::Ext::AppTypes::WORKER)
        expect(span.service).to eq('qless')
        expect(span).to have_error_message(error_message)
        expect(span).to have_error
        expect(span).to have_error_type(error_class_name)
      end
    end
  end

  context 'without forking' do
    let(:worker) { Qless::Workers::SerialWorker.new(reserver) }

    it_should_behave_like 'job execution tracing'

    it 'ensures worker is not using forking' do
      expect(worker.class).to eq(Qless::Workers::SerialWorker)
    end
  end

  describe 'patching for workers' do
    let(:worker_class_1) { Class.new }
    let(:worker_class_2) { Class.new }

    before(:each) do
      # Remove the patch so it applies new patch
      remove_patch!(:qless)

      # Re-apply patch, to workers
      Datadog.configure do |c|
        c.use(:qless, workers: [worker_class_1, worker_class_2])
      end
    end

    it 'adds the instrumentation module' do
      expect(worker_class_1.singleton_class.included_modules).to include(Datadog::Contrib::Qless::QlessJob)
      expect(worker_class_2.singleton_class.included_modules).to include(Datadog::Contrib::Qless::QlessJob)
    end
  end
end
