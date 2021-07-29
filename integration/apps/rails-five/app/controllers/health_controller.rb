class HealthController < ApplicationController
  #
  # Check if web application is responsive
  # Return 204 No Content to signal healthy state.
  #
  def check
    head :no_content
  end

  def profiling_check
    return render(body: "Profiler not running\n", status: 503) unless Datadog.profiler

    ["Datadog::Profiling::Collectors::Stack", "Datadog::Profiling::Scheduler"].each do |name|
      return render(body: "Profiler thread missing: #{name}\n", status: 503) unless Thread.list.map(&:name).include?(name)
    end

    render body: "Profiling check OK\n"
  end
end
