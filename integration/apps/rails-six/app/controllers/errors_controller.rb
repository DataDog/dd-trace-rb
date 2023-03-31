
class ErrorsController < ApplicationController
  def server_error
    # Make the span visible from graph
    sleep 0.1
    render plain: "OK"
  end
end
