require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/qless/integration'
require_relative 'support/job'

require 'ddtrace'

RSpec.describe 'Qless instrumentation' do
  include_context 'Qless job'

  let(:configuration_options) { {} }

  before do
    delete_all_redis_keys

    # Patch Qless
    Datadog.configure do |c|
      c.tracing.instrument :qless, configuration_options
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
      before do
        perform_job(job_class, job_args)
      end

      it 'is traced' do
        expect(spans).to have(1).items
        expect(failed_jobs.count).to eq(0)
        expect(span.name).to eq('qless.job')
        expect(span.resource).to eq(job_class.name)
        expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::AppTypes::TYPE_WORKER)
        expect(span.service).to eq(tracer.default_service)
        expect(span).to_not have_error
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('qless')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('job')
        expect(span.get_tag('span.kind')).to eq('consumer')
        expect(span.get_tag('messaging.system')).to eq('qless')
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Qless::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Qless::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', true
    end

    context 'that fails' do
      before do
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
        expect(span.span_type).to eq(Datadog::Tracing::Metadata::Ext::AppTypes::TYPE_WORKER)
        expect(span.service).to eq(tracer.default_service)
        expect(span).to have_error_message(error_message)
        expect(span).to have_error
        expect(span).to have_error_type(error_class_name)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('qless')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('job')
        expect(span.get_tag('span.kind')).to eq('consumer')
        expect(span.get_tag('messaging.system')).to eq('qless')
      end
    end
  end

  context 'without forking' do
    let(:worker) { Qless::Workers::SerialWorker.new(reserver) }

    it_behaves_like 'job execution tracing'

    it 'ensures worker is not using forking' do
      expect(worker.class).to eq(Qless::Workers::SerialWorker)
    end

    describe 'patching for workers' do
      it 'adds the instrumentation module' do
        expect(worker.singleton_class.included_modules).to include(Datadog::Tracing::Contrib::Qless::QlessJob)
      end
    end
  end

  context 'with forking' do
    before do
      skip 'Fork not supported on current platform' unless Process.respond_to?(:fork)

      # Ensures worker is using forking
      expect(worker.class).to eq(Qless::Workers::ForkingWorker)
    end

    context 'trace context' do
      subject(:perform) do
        tracer.trace('parent.process') do |span|
          @parent_span = span
          perform_job(job_class)
        end

        expect(failed_jobs.count).to eq(0)
      end

      context 'on main process' do
        it 'only contains parent process spans' do
          perform

          expect(span.name).to eq('parent.process')
        end
      end

      context 'on child process' do
        it 'does not include parent process spans' do
          expect(job_class).to receive(:perform) do
            # Mock #shutdown! in fork only
            expect(tracer).to receive(:shutdown!).and_wrap_original do |m, *args|
              m.call(*args)

              expect(span.name).to eq('qless.job')
              expect(span).to have_distributed_parent(@parent_span)
              expect(span.get_tag('messaging.system')).to eq('qless')
            end
          end

          perform

          # Remove hard-expectation from parent process,
          # as `job_class#perform` won't be called in this process.
          RSpec::Mocks.space.proxy_for(job_class).reset
        end
      end
    end
  end
end
