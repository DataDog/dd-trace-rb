LogHelpers.without_warnings do
  require 'resque'
end

require 'ddtrace/contrib/resque/resque_job'

RSpec.shared_context 'Resque job' do
  def perform_job(klass, *args)
    job = Resque::Job.new(queue_name, 'class' => klass, 'args' => args)
    worker.perform(job)
  end

  let(:queue_name) { :test_queue }
  let(:worker) { Resque::Worker.new(queue_name) }
  let(:job_class) do
    stub_const('TestJob', Module.new).tap do |mod|
      mod.send(:extend, Datadog::Contrib::Resque::ResqueJob)
      mod.send(:define_singleton_method, :perform) do
        # Do nothing by default.
      end
    end
  end
end
