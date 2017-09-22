require 'resque'
require 'ddtrace'
require 'ddtrace/contrib/resque/resque_job'

def perform_job(klass, *args)
  resque_job = Resque::Job.new(:test_queue, 'class' => klass, 'args' => args)
  resque_job.perform
end

module TestJob
  extend Datadog::Contrib::ResqueJob

  def self.perform(pass = true)
    return true if pass
    raise StandardError, 'TestJob failed'
  end
end
