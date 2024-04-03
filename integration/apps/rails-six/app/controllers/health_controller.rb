require 'json'

class HealthController < ApplicationController
  #
  # Check if web application is responsive
  # Return 204 No Content to signal healthy state.
  #
  def check
    head :no_content
  end

  def detailed_check
    render json: {
      webserver_process: $PROGRAM_NAME,
      profiler_available: Datadog::Profiling.start_if_enabled,
      profiler_threads: Thread.list.map(&:name).select { |it| it && it.include?('Profiling') },
      telemetry_enabled: Datadog.configuration.telemetry.enabled,
      telemetry_client_enabled: Datadog.send(:components).telemetry.enabled,
    }
  end
end
