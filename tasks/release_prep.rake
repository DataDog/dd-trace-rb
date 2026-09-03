# frozen_string_literal: true

require_relative "release_notes"
require_relative "release_body"

# Release-prep tasks for `.github/workflows/release-prep.yml`, which runs
# each as a separate step, in order:
#
#   release_prep:validate[v] -> release_prep:release_body -> `gh release create --draft`
#     -> release_prep:changelog[v] -> version:bump[v]
#
# `release_prep:changelog` consumes (deletes) exactly the unreleased/ files it
# rendered, so it runs only after the draft release exists; a failed earlier
# step stops the workflow and leaves the source fragments intact.

namespace :release_prep do
  desc "Check that the given version is an official release version (e.g. release_prep:validate[2.36.0])"
  task :validate, [:version] do |_t, args|
    validate_official_version!(args[:version])
    puts "Version #{args[:version]} is a valid official release version."
  end

  desc "Render the pending unreleased/ fragments into the GitHub release body (#{ReleaseNotes::ReleaseBody::OUTPUT_FILE})"
  task :release_body do
    ReleaseNotes::ReleaseBody.write
    ReleaseNotes::ReleaseBody.pimp!
  end

  desc "Insert the pending unreleased/ fragments into CHANGELOG.md and rewrite the compare-link footer (e.g. release_prep:changelog[2.36.0])"
  task :changelog, [:version] do |_t, args|
    version = validate_official_version!(args[:version])

    previous = ReleaseNotes.previous_version
    entries = ReleaseNotes::Fragments.read_all
    highlights_path = "unreleased/highlights.md"

    ReleaseNotes.insert_changelog(version, ReleaseNotes::Fragments.render(entries))
    Rake::Task["changelog:format"].invoke
    ReleaseNotes.rewrite_footer(version, previous)

    # Runs last: only delete the source fragments once the draft release and
    # CHANGELOG.md have both been written successfully.
    ReleaseNotes::Fragments.consume!(entries, highlights_path: highlights_path)
  end

  # Only official releases are prepared: a well-formed MAJOR.MINOR.PATCH
  # version with no pre-release segment (e.g. 2.36.0, but not 2.36.0.beta1,
  # 2.36.0.rc1, or a partial version like 2.36).
  def validate_official_version!(version)
    version = version.to_s
    invalid_version = "Invalid version '#{version}' (expected an official release, e.g. 2.36.0)"
    ReleaseNotes.fail!(invalid_version) unless Gem::Version.correct?(version)
    Gem::Version.new(version).tap { |v| ReleaseNotes.fail!(invalid_version) if v.prerelease? || v.segments.length != 3 }
  end
end
