# frozen_string_literal: true

require "date"
require "pimpmychangelog"
require_relative "../release_prep"

# The CHANGELOG.md file: #release is the entry point — it renders the given
# Fragments collection into a new version section under [Unreleased],
# linkifies (#NNNN)/(@handle) tokens, rewrites the compare-link footer, and
# writes the file once. PimpMyChangelog is required, not guarded: preparing a
# release without linkification must fail loudly, never degrade silently.
module ReleasePrep
  class Changelog
    PREVIOUS_VERSION_PATTERN = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/v(.+?)\.\.\.master}
    UNRELEASED_FOOTER_PATTERN = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/.*?\.\.\.master}

    def initialize(path: "CHANGELOG.md")
      @path = path
    end

    def release(version, fragments)
      source = File.read(@path)
      previous = previous_version_in(source)
      user, project = REPO.split("/", 2)
      inserted = insert_version_in(source, version, fragments.render)
      linkified = PimpMyChangelog::Pimper.new(user, project, inserted).better_changelog

      File.write(@path, rewrite_footer_in(linkified, version, previous))
    end

    private

    def previous_version_in(source)
      match = source.match(PREVIOUS_VERSION_PATTERN)
      ReleasePrep.fail!("Could not find the [Unreleased] compare link in #{@path}") unless match

      match[1]
    end

    def insert_version_in(source, version, content)
      match = source.match(/\n## \[Unreleased\]/)
      ReleasePrep.fail!("Could not find [Unreleased] marker in #{@path}") unless match

      section = "\n## [#{version}] - #{Date.today}\n\n#{content}".rstrip
      source.insert(match.end(0), "\n#{section}")
    end

    def rewrite_footer_in(source, version, previous)
      replacement =
        "[Unreleased]: #{REPO_URL}/compare/v#{version}...master\n" \
        "[#{version}]: #{REPO_URL}/compare/v#{previous}...v#{version}"

      unless source.match?(UNRELEASED_FOOTER_PATTERN)
        ReleasePrep.fail!("Could not find [Unreleased] compare link in #{@path}")
      end

      source.sub(UNRELEASED_FOOTER_PATTERN, replacement)
    end
  end
end
