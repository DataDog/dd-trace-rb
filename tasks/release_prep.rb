# frozen_string_literal: true

# Namespace and shared helpers for the release-prep tooling
# (tasks/release_prep/*.rb, tasks/release_prep.rake).
module ReleasePrep
  REPO = "DataDog/dd-trace-rb"
  REPO_URL = "https://github.com/#{REPO}"

  class ValidationError < StandardError; end

  module_function

  def fail!(message)
    abort "::error::#{message}"
  end
end
