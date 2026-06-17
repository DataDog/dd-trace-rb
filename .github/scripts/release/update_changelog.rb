# frozen_string_literal: true

# Edits CHANGELOG.md as part of the release-prep workflow.
#
# Two subcommands, run in this order around `rake changelog:format` (so the
# formatter does not clobber the freshly-written footer links):
#
#   ruby update_changelog.rb insert   # add the new "## [X.Y.Z] - <date>" section
#   bundle exec rake changelog:format
#   ruby update_changelog.rb footer   # rewrite the [Unreleased]/[X.Y.Z] compare links
#
# Ports FastCastle's FileEditor.insert_after / FileEditor.replace semantics.
#
# Environment:
#   VERSION           release version, no "v" prefix (e.g. "2.36.0")          [required]
#   PREVIOUS_VERSION  previous released version for the compare link          [footer only]
#   BODY_FILE         path to the approved draft release body                 [insert only]
#   CHANGELOG_FILE    path to the changelog (default: "CHANGELOG.md")
#   REPO_URL          repository URL (default: "https://github.com/DataDog/dd-trace-rb")

require "date"

# Marker that separates release "highlights" (release-page only) from the
# changelog body. FastCastle inserts it into the draft release body. When it is
# absent we fall back to using the whole body.
CHANGELOG_MARKER = "<!-- changelog -->"

REPO_URL = ENV.fetch("REPO_URL", "https://github.com/DataDog/dd-trace-rb")
CHANGELOG_FILE = ENV.fetch("CHANGELOG_FILE", "CHANGELOG.md")

def extract_changelog(body)
  section = body.include?(CHANGELOG_MARKER) ? body.split(CHANGELOG_MARKER, 2).last : body
  section.strip
end

def insert
  version = ENV.fetch("VERSION")
  body = File.read(ENV.fetch("BODY_FILE"))
  changelog = extract_changelog(body)

  content = File.read(CHANGELOG_FILE)
  match = content.match(/\[Unreleased\]/)
  raise "Could not find [Unreleased] marker in #{CHANGELOG_FILE}" unless match

  section = "\n## [#{version}] - #{Date.today}\n\n#{changelog}".rstrip
  content = content.insert(match.end(0), "\n#{section}")
  File.write(CHANGELOG_FILE, content)
end

def footer
  version = ENV.fetch("VERSION")
  previous_version = ENV.fetch("PREVIOUS_VERSION")

  content = File.read(CHANGELOG_FILE)
  pattern = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/.*?\.\.\.master}o
  replacement =
    "[Unreleased]: #{REPO_URL}/compare/v#{version}...master\n" \
    "[#{version}]: #{REPO_URL}/compare/v#{previous_version}...v#{version}"

  raise "Could not find [Unreleased] compare link in #{CHANGELOG_FILE}" unless content.match?(pattern)

  content = content.sub(pattern, replacement)
  File.write(CHANGELOG_FILE, content)
end

case ARGV[0]
when "insert" then insert
when "footer" then footer
else
  abort "usage: #{File.basename($PROGRAM_NAME)} {insert|footer}"
end
