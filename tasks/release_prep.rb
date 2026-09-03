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

  # A release must have something to announce: changelog fragments, release
  # highlights, or both. Guarding here keeps the same rule and message in one
  # place for every release-prep entry point.
  def fail_if_nothing_to_release!(fragments, highlights)
    return unless fragments.empty? && highlights.empty?

    fail!("No changelog fragments and no highlights found in unreleased/; nothing to release")
  end
end

require_relative "release_prep/changelog"
require_relative "release_prep/fragments"
require_relative "release_prep/highlights"
require_relative "release_prep/release_notes"
