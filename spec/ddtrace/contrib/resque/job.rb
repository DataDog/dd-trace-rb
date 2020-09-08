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
    stub_const('TestJob', Class.new).tap do |mod|
      mod.send(:extend, Datadog::Contrib::Resque::ResqueJob)
      mod.send(:define_singleton_method, :perform) do |*args|
        # Do nothing by default.
      end
    end
  end
  let(:job_args) { nil }

  before(:each) do
    Resque.after_fork { Datadog::Pin.get_from(Resque).tracer.writer = FauxWriter.new }
    Resque.before_first_fork.each(&:call)
  end
end
