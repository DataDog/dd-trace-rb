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

  # Squash-merge commit subjects end with "(#NNNN)" and merge commits open
  # with "Merge pull request #NNNN", so every PR that ever landed in this
  # repository appears in a commit subject line.
  def merged_pr_numbers(commit_subjects: git_commit_subjects)
    commit_subjects.flat_map do |subject|
      [subject.match(/\(#(\d+)\)\z/)&.captures&.first, subject.match(/\AMerge pull request #(\d+) /)&.captures&.first]
    end.compact.uniq
  end

  def git_commit_subjects
    `git log --format=%s`.split("\n")
  end

  # A fragment reaches release-prep only through its pull request, so a PR
  # number absent from this repository's history is a hallucination or typo
  # that would otherwise ship as a dead CHANGELOG.md link. Per-PR CI cannot
  # check this: the fragment references the PR it is still riding in.
  def validate_pr_numbers!(fragments, pr_numbers: merged_pr_numbers)
    errors = fragments.map do |fragment|
      next if pr_numbers.include?(fragment.pr_number)

      "#{fragment.path}: pull_request does not match any merged PR in this repository (##{fragment.pr_number})"
    end.compact
    fail_all!(errors) unless errors.empty?
  end
end

require_relative "release_prep/changelog"
require_relative "release_prep/fragments"
require_relative "release_prep/highlights"
require_relative "release_prep/release_notes"
