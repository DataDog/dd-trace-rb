class HealthController < ApplicationController
  #
  # Check if web application is responsive
  # Return 204 No Content to signal healthy state.
  #
  def check
    head :no_content
  end
end
