# frozen_string_literal: true

require_relative "release_notes"

namespace :changelog do
  desc "Validate unreleased/*.json changelog fragments (schema only; message hygiene is checked by CI's vale step)"
  task :lint do
    ReleaseNotes::Fragments.read_all
    ReleaseNotes::Fragments.validate_examples!
    puts "All unreleased/ changelog fragments are valid."
  rescue ReleaseNotes::Fragments::ValidationError => e
    abort "::error::#{e.message}"
  end

  desc "Render the pending unreleased/ changelog fragments as they would appear in CHANGELOG.md"
  task :render do
    entries = ReleaseNotes::Fragments.read_all
    highlights_path = "unreleased/highlights.md"
    highlights = File.exist?(highlights_path) ? File.read(highlights_path) : nil

    rendered = ReleaseNotes::Fragments.render(entries, highlights: highlights)
    puts rendered.empty? ? "(no pending changelog fragments)" : rendered
  end
end
