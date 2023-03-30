class JobsController < ApplicationController
  def create
    job_id = SecureRandom.uuid

    AnotherTestJob.perform_later(job_id: SecureRandom.uuid)

    render json: { job_id: job_id }
  end
end
