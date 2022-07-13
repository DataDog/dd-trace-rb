class BasicController < ApplicationController
  def create
    # Queue job
    job_id = SecureRandom.uuid
    BasicJob.perform_async(job_id, 5)

    # Return response
    render json: { job_id: job_id }
  end
end
