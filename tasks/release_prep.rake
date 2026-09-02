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

    entries = ReleaseNotes::Fragments.read_all
    highlights_path = "unreleased/highlights.md"
    highlights = File.exist?(highlights_path) ? File.read(highlights_path) : nil

    ReleaseNotes.fail!("No changelog fragments and no highlights found in unreleased/; nothing to release") if entries.empty? && highlights.to_s.strip.empty?

    # Highlights are release-page-only (see unreleased/README.md); the release
    # body and CHANGELOG.md are rendered separately so they don't leak in.
    release_body = ReleaseNotes::Fragments.render(entries, highlights: highlights)
    changelog = ReleaseNotes::Fragments.render(entries)

    ReleaseNotes.create_draft_release(version, release_body)

    # `render` already pimped `changelog` with its own link-definition block; inserting
    # that block mid-file would give the file two, and PimpMyChangelog::Parser#content
    # truncates on the *first* separator it finds, silently dropping everything after
    # it. `changelog:format` re-pimps the whole file below, so strip the block back off
    # before inserting.
    changelog = changelog.split(PimpMyChangelog::Pimper::SEPARATOR).first.to_s.rstrip
    ReleaseNotes.insert_changelog(version, changelog)
    Rake::Task["changelog:format"].invoke
    ReleaseNotes.rewrite_footer(version, previous)

    # Runs last: only delete the source fragments once the draft release and
    # CHANGELOG.md have both been written successfully.
    ReleaseNotes::Fragments.consume!(entries, highlights_path: highlights_path)

    # `version:bump` also asserts the resulting gemspec matches the version.
    Rake::Task["version:bump"].invoke(version)
  end
end
