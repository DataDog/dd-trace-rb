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

  # Reports every violation as its own annotation, then exits once.
  def fail_all!(errors)
    errors.each { |error| warn "::error::#{error}" }
    abort
  end

  # Linting reports everything wrong with unreleased/ in one run, not one
  # violation per CI round-trip.
  def validate_fragments!(fragments)
    errors = fragments.validate
    fail_all!(errors) unless errors.empty?
  end

  # A release must have changelog fragments; highlights are optional and
  # cannot constitute a release on their own. Guarding here keeps the rule
  # and message in one place for every release-prep entry point.
  def fail_if_no_fragments!(fragments)
    return unless fragments.empty?

    fail!("No changelog fragments found in unreleased/; nothing to release")
  end
end

require_relative "release_prep/changelog"
require_relative "release_prep/fragments"
require_relative "release_prep/highlights"
require_relative "release_prep/release_notes"
