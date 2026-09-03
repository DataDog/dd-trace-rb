# frozen_string_literal: true

# Namespace and shared helpers for the release-prep tooling
# (tasks/release_prep/*.rb, tasks/release_prep.rake). Requiring this file
# loads all the objects.
module ReleasePrep
  REPO = "DataDog/dd-trace-rb"
  REPO_URL = "https://github.com/#{REPO}"

  class ValidationError < StandardError; end

  module_function

  def fail!(message)
    abort "::error::#{message}"
  end
end

require_relative "release_prep/changelog"
require_relative "release_prep/fragments"
require_relative "release_prep/highlights"
require_relative "release_prep/release_notes"
