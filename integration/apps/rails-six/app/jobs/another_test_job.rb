class AnotherTestJob < ApplicationJob
  @queue = :default

  def perform(params)
    Logger.new(STDOUT).debug("Working: #{params[:job_id]}")

    raise "This is a debug job to test Datadog" if rand > 0.5
  end
end
