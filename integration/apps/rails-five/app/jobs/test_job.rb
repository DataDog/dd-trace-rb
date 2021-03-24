require 'ddtrace/contrib/resque/resque_job'

module Jobs
  class Test
    extend Datadog::Contrib::Resque::ResqueJob
    @queue = :default

    def self.perform(params)
      Logger.new(STDOUT).debug("Working: #{params[:job_id]}")
    end
  end
end
