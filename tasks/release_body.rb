# frozen_string_literal: true

require "fileutils"
require_relative "release_notes"

if Gem.loaded_specs.key?("pimpmychangelog")
  require "pimpmychangelog"
end

module ReleaseNotes
  module ReleaseBody
    OUTPUT_FILE = "tmp/release_body.md"

    module_function

    # Writes the pending unreleased/ fragments (plus highlights, if present)
    # as plain Markdown to `path`, for use as the GitHub release body.
    # `Fragments.render` deliberately does not linkify; `pimp!` does it
    # separately so specs never depend on the pimpmychangelog gem.
    def write(dir: "unreleased", path: OUTPUT_FILE)
      entries = Fragments.read_all(dir: dir)
      highlights_path = File.join(dir, "highlights.md")
      highlights = File.exist?(highlights_path) ? File.read(highlights_path) : nil

      if entries.empty? && highlights.to_s.strip.empty?
        ReleaseNotes.fail!("No changelog fragments and no highlights found in #{dir}/; nothing to release")
      end

      body = Fragments.render(entries, highlights: highlights)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
      path
    end

    # Linkifies #NNNN/@handle in the written file. Kept separate from `write`
    # because PimpMyChangelog's CLI only understands CHANGELOG.md, so the
    # Pimper is invoked directly here.
    def pimp!(path: OUTPUT_FILE)
      unless defined?(PimpMyChangelog)
        ReleaseNotes.fail!("pimpmychangelog gem is required to linkify the release body")
      end

      body = File.read(path)
      File.write(path, PimpMyChangelog::Pimper.new(*ReleaseNotes::REPO.split("/"), body).better_changelog)
      path
    end
  end
end
