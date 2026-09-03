# frozen_string_literal: true

require "fileutils"
require_relative "../release_prep"
require_relative "fragments"

if Gem.loaded_specs.key?("pimpmychangelog")
  require "pimpmychangelog"
end

# The GitHub release being prepared: its tag name and the release notes body
# written for `gh release create --draft --notes-file`. Representation only;
# the workflow owns the actual release creation.
module ReleasePrep
  class ReleaseNotes
    OUTPUT_FILE = "tmp/release_body.md"

    def initialize(version:, fragments:, highlights: nil)
      @version = version
      @fragments = fragments
      @highlights = highlights
    end

    def tag_name
      "v#{@version}"
    end

    def empty?
      @fragments.empty? && @highlights.to_s.strip.empty?
    end

    def body
      @fragments.render(highlights: @highlights)
    end

    def write(path: OUTPUT_FILE)
      ReleasePrep.fail!("No changelog fragments and no highlights found in unreleased/; nothing to release") if empty?

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
      path
    end

    # Linkifies #NNNN/@handle in the written file. Kept separate from `write`
    # because the specs run without the pimpmychangelog gem in some CI test
    # environments, and the CLI only operates on CHANGELOG.md, so the Pimper
    # is invoked directly here.
    def linkify!(path: OUTPUT_FILE)
      unless defined?(PimpMyChangelog)
        ReleasePrep.fail!("pimpmychangelog gem is required to linkify the release notes")
      end

      File.write(path, PimpMyChangelog::Pimper.new(*ReleasePrep::REPO.split("/"), File.read(path)).better_changelog)
      path
    end
  end
end
