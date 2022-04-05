require "#{Rails.root}/app/jobs/test_job"

class BasicController < ApplicationController
  # Reads & writes from cache, reads from DB, and queues a Resque job.
  #
  # Example trace:
  #
  # ----------------------- Rack -----------------------------
  #    -------------- ActionController --------------------
  #      --- ActiveSupport -- ActiveRecord -- Resque ---
  #        ----- Redis ----                 -- Redis --
  #
  def default
    # Read from the database
    records = Test.where(version: 0)

    # Queue job
    Resque.enqueue(TestJob, job_id: request.request_id, records: records.map(&:to_json))

    # Return response
    render json: { job_id: request.request_id }
  end

  # Runs a recursive implementation of fibonacci.
  # Provides a basic load on CPU, stack frames, response time.
  def fibonacci
    fib(rand(25..35))
    head :ok
  end

  private

  def fib(n)
    n <= 1 ? n : fib(n-1) + fib(n-2)
  end
end
