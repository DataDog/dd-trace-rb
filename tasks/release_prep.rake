# frozen_string_literal: true

require_relative "release_notes"

# Release-prep logic for the `release_prep:prepare` task, invoked by
# `.github/workflows/release-prep.yml`.
#
# The version is passed as a task argument, e.g.
#   rake "release_prep:prepare[2.36.0]"

# Only official releases are prepared here: a well-formed MAJOR.MINOR.PATCH
# version with no pre-release segment (e.g. 2.36.0, but not 2.36.0.beta1,
# 2.36.0.rc1, or a partial version like 2.36).
namespace :release_prep do
  desc "Prepare a release: write the changelog and bump the gem version (e.g. release_prep:prepare[2.36.0])"
  task :prepare, [:version] do |_t, args|
    version = args[:version] || raise(ArgumentError, 'Please provide a version, e.g. rake "release_prep:prepare[2.36.0]"')

    invalid_version = "Invalid version '#{version}' (expected an official release, e.g. 2.36.0)"
    ReleaseNotes.fail!(invalid_version) unless Gem::Version.correct?(version)
    Gem::Version.new(version).tap { |v| ReleaseNotes.fail!(invalid_version) if v.prerelease? || v.segments.length != 3 }

    previous = ReleaseNotes.previous_version
    changelog = ReleaseNotes.draft_changelog(version)

    ReleaseNotes.insert_changelog(version, changelog)
    Rake::Task["changelog:format"].invoke
    ReleaseNotes.rewrite_footer(version, previous)

    # `version:bump` also asserts the resulting gemspec matches the version.
    Rake::Task["version:bump"].invoke(version)
  end
end
