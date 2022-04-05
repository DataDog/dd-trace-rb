require 'datadog/tracing/contrib/resque/resque_job'

class TestJob
  extend Datadog::Tracing::Contrib::Resque::ResqueJob
  @queue = :default

  def self.perform(params)
    Logger.new(STDOUT).debug("Working: #{params[:job_id]}")
  end
end
