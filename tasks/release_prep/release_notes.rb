# frozen_string_literal: true

require "fileutils"
require_relative "../release_prep"
require_relative "fragments"

# The GitHub release being prepared: its tag name and the release notes body
# written for `gh release create --draft --notes-file`. The body is plain
# Markdown (GitHub auto-links #NNNN and @handle); CHANGELOG.md's own
# linkified house style comes from the repo's changelog:format pass.
# Representation only; the workflow owns the actual release creation.
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
  end
end
