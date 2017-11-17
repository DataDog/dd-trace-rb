require 'resque'

require 'ddtrace'
require 'ddtrace/contrib/resque/resque_job'

def perform_job(klass, *args)
  worker = Resque::Worker.new(:test_queue)
  job = Resque::Job.new(:test_queue, 'class' => klass, 'args' => args)
  worker.perform(job)
end

module TestJob
  extend Datadog::Contrib::Resque::ResqueJob

  def self.perform(pass = true)
    return true if pass
    raise StandardError, 'TestJob failed'
  end
end

module TestCleanStateJob
  extend Datadog::Contrib::Resque::ResqueJob

  def self.perform(tracer)
    # the perform ensures no Context is propagated
    pin = Datadog::Pin.get_from(Resque)
    spans = pin.tracer.provider.context.trace.length
    raise StandardError if spans != 1
  end
end

Datadog::Monkey.patch_module(:resque)
Resque.after_fork { Datadog::Pin.get_from(Resque).tracer.writer = FauxWriter.new }
Resque.before_first_fork.each(&:call)
