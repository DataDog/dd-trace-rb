# frozen_string_literal: true

require "date"
require_relative "../release_prep"

# The CHANGELOG.md file: reads the previous version from its footer, inserts a
# new version section under [Unreleased], and rewrites the compare links.
module ReleasePrep
  class Changelog
    PREVIOUS_VERSION_PATTERN = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/v(.+?)\.\.\.master}
    UNRELEASED_FOOTER_PATTERN = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/.*?\.\.\.master}

    def initialize(path: "CHANGELOG.md")
      @path = path
    end

    def previous_version
      match = File.read(@path).match(PREVIOUS_VERSION_PATTERN)
      ReleasePrep.fail!("Could not find the [Unreleased] compare link in #{@path}") unless match

      match[1]
    end

    def insert_version(version, content)
      match = File.read(@path).match(/\[Unreleased\]/)
      ReleasePrep.fail!("Could not find [Unreleased] marker in #{@path}") unless match

      section = "\n## [#{version}] - #{Date.today}\n\n#{content}".rstrip
      File.write(@path, File.read(@path).insert(match.end(0), "\n#{section}"))
    end

    def rewrite_footer(version, previous)
      replacement =
        "[Unreleased]: #{REPO_URL}/compare/v#{version}...master\n" \
        "[#{version}]: #{REPO_URL}/compare/v#{previous}...v#{version}"

      content = File.read(@path)
      unless content.match?(UNRELEASED_FOOTER_PATTERN)
        ReleasePrep.fail!("Could not find [Unreleased] compare link in #{@path}")
      end

      File.write(@path, content.sub(UNRELEASED_FOOTER_PATTERN, replacement))
    end
  end
end
