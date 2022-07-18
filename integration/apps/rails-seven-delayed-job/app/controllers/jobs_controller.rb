require "#{Rails.root}/app/jobs/test_job"

class JobsController < ApplicationController
  def create
    # Queue job
    job_id = SecureRandom.uuid
    TestJob.perform_later(job_id)

    # Return response
    render json: { job_id: job_id }
  end
end
