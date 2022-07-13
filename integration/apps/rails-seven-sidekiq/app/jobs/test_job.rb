class TestJob < ApplicationJob
  queue_as :default

  def perform(*args)
    Delayed::Job.all
    sleep 8
    puts "Job #{Time.now}"
  end
end
