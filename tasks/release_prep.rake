# frozen_string_literal: true

require_relative "lib/release_prep"

# Each task is one step of `.github/workflows/release-prep.yml`, which runs
# them in order and owns the pipeline's failure semantics.

namespace :release_prep do
  desc "Check that the given version is an official release version (e.g. release_prep:validate[2.36.0])"
  task :validate, [:version] do |_t, args|
    validate_official_version!(args[:version])
    puts "Version #{args[:version]} is a valid official release version."
  end

  desc "Render the pending unreleased/ fragments into the GitHub release body (#{ReleasePrep::ReleaseNotes::OUTPUT_FILE})"
  task :release_body, [:version] do |_t, args|
    version = validate_official_version!(args[:version])

    fragments = ReleasePrep::Fragments.read_all
    ReleasePrep.validate_fragments!(fragments)
    release_notes = ReleasePrep::ReleaseNotes.new(
      version: version,
      fragments: fragments,
      highlights: ReleasePrep::Highlights.read,
    )

    release_notes.write
  rescue ReleasePrep::ValidationError => e
    ReleasePrep.fail!(e.message)
  end

  desc "Insert the pending unreleased/ fragments into CHANGELOG.md and rewrite the compare-link footer (e.g. release_prep:changelog[2.36.0])"
  task :changelog, [:version] do |_t, args|
    version = validate_official_version!(args[:version])

    fragments = ReleasePrep::Fragments.read_all
    highlights = ReleasePrep::Highlights.read

    ReleasePrep.validate_fragments!(fragments)
    ReleasePrep.fail_if_no_fragments!(fragments)

    ReleasePrep::Changelog.new.release(version, fragments)

    # Runs last: only delete the source files once the draft release and
    # CHANGELOG.md have both been written successfully.
    fragments.consume!
    highlights.delete!
  rescue ReleasePrep::ValidationError => e
    ReleasePrep.fail!(e.message)
  end

  # Official releases only: not 2.36.0.beta1, 2.36.0.rc1, or a partial 2.36.
  def validate_official_version!(version)
    version = version.to_s
    invalid_version = "Invalid version '#{version}' (expected an official release, e.g. 2.36.0)"
    ReleasePrep.fail!(invalid_version) unless Gem::Version.correct?(version)
    Gem::Version.new(version).tap { |v| ReleasePrep.fail!(invalid_version) if v.prerelease? || v.segments.length != 3 }
  end
end
