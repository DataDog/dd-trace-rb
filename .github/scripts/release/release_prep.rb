# frozen_string_literal: true

# CLI used by the "Prepare release" workflow (.github/workflows/release-prep.yml).
#
# Each subcommand is a single, side-effecting release-prep step. They run in
# this order so the changelog footer is rewritten *after* `rake changelog:format`
# (otherwise pimpmychangelog reformats the line out from under the footer rewrite):
#
#   ruby release_prep.rb validate-version
#   ruby release_prep.rb resolve-previous-version
#   ruby release_prep.rb read-draft-release
#   ruby release_prep.rb insert-changelog
#   bundle exec rake changelog:format
#   ruby release_prep.rb rewrite-footer
#   ...
#   ruby release_prep.rb verify-version
#
# Ports FastCastle's FileEditor.insert_after / FileEditor.replace semantics.
#
# Environment:
#   VERSION           release version, no "v" prefix (e.g. "2.36.0")                  [required]
#   PREVIOUS_VERSION  previous released version for the compare link                  [footer]
#   BODY_FILE         where the draft body is written/read                            [read/insert]
#   GITHUB_TOKEN      token used to read the draft release (dd-octo-sts output)       [read]
#   GITHUB_REPOSITORY "owner/repo", provided by GitHub Actions                        [read]
#   GITHUB_ENV        Actions env file, appended to by resolve-previous-version
#   CHANGELOG_FILE    path to the changelog (default: "CHANGELOG.md")
#   REPO_URL          repository URL (default: "https://github.com/DataDog/dd-trace-rb")

require "date"
require "json"
require "net/http"
require "rubygems"

module ReleasePrep
  # Separates release "highlights" (release-page only) from the changelog body in
  # the draft release. When the marker is absent we fall back to the whole body.
  CHANGELOG_MARKER = "<!-- changelog -->"

  REPO_URL = ENV.fetch("REPO_URL", "https://github.com/DataDog/dd-trace-rb")
  CHANGELOG_FILE = ENV.fetch("CHANGELOG_FILE", "CHANGELOG.md")

  module_function

  def version
    ENV.fetch("VERSION")
  end

  def fail!(message)
    abort "::error::#{message}"
  end

  # Reject anything that is not MAJOR.MINOR.PATCH with an optional suffix.
  def validate_version
    fail!("Invalid version '#{version}' (expected e.g. 2.36.0)") unless version.match?(/\A\d+\.\d+\.\d+([._-].+)?\z/)
    puts "Version '#{version}' is valid"
  end

  # Use the explicit input when given, otherwise the latest v* tag. Exported to
  # later steps via the Actions env file so the footer step can read it.
  def resolve_previous_version
    previous = ENV["PREVIOUS_VERSION"].to_s.strip
    if previous.empty?
      tags = `git tag --list 'v*' --sort=-version:refname`.lines.map(&:strip).reject(&:empty?)
      previous = tags.first.to_s.sub(/\Av/, "")
    end
    fail!("Could not determine previous version (no v* tags found); pass previous_version explicitly") if previous.empty?

    puts "Using previous version: #{previous}"
    File.open(ENV.fetch("GITHUB_ENV"), "a") { |f| f.puts("PREVIOUS_VERSION=#{previous}") }
  end

  # Fetch the approved draft release body for tag vX.Y.Z and write it to BODY_FILE.
  def read_draft_release
    tag = "v#{version}"
    draft = releases.find { |release| release["tag_name"] == tag && release["draft"] == true }
    fail!("No draft release found with tag #{tag}. Please create and approve a draft release first.") unless draft

    body = draft["body"].to_s
    File.write(ENV.fetch("BODY_FILE"), body)
    puts "Wrote draft release body for #{tag} (#{body.length} chars)"
  end

  # Insert the new "## [X.Y.Z] - <date>" section right after the [Unreleased] marker.
  def insert_changelog
    changelog = extract_changelog(File.read(ENV.fetch("BODY_FILE")))

    content = File.read(CHANGELOG_FILE)
    match = content.match(/\[Unreleased\]/)
    fail!("Could not find [Unreleased] marker in #{CHANGELOG_FILE}") unless match

    section = "\n## [#{version}] - #{Date.today}\n\n#{changelog}".rstrip
    File.write(CHANGELOG_FILE, content.insert(match.end(0), "\n#{section}"))
  end

  # Rewrite the [Unreleased]/[X.Y.Z] compare links in the changelog footer.
  def rewrite_footer
    previous = ENV.fetch("PREVIOUS_VERSION")
    pattern = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/.*?\.\.\.master}o
    replacement =
      "[Unreleased]: #{REPO_URL}/compare/v#{version}...master\n" \
      "[#{version}]: #{REPO_URL}/compare/v#{previous}...v#{version}"

    content = File.read(CHANGELOG_FILE)
    fail!("Could not find [Unreleased] compare link in #{CHANGELOG_FILE}") unless content.match?(pattern)

    File.write(CHANGELOG_FILE, content.sub(pattern, replacement))
  end

  # Confirm `rake version:bump` produced the version we asked for.
  def verify_version
    gemspec = Dir.glob("*.gemspec").first
    actual = Gem::Specification.load(gemspec).version.to_s
    fail!("Gemspec version '#{actual}' does not match requested version '#{version}'") unless actual == version
    puts "Gemspec version '#{actual}' matches the requested version"
  end

  def extract_changelog(body)
    section = body.include?(CHANGELOG_MARKER) ? body.split(CHANGELOG_MARKER, 2).last : body
    section.strip
  end

  def releases
    repo = ENV.fetch("GITHUB_REPOSITORY")
    uri = URI("https://api.github.com/repos/#{repo}/releases?per_page=100")

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{ENV.fetch("GITHUB_TOKEN")}"
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["User-Agent"] = "dd-trace-rb-release-prep"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    fail!("GitHub API request failed: #{response.code} #{response.body}") unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  COMMANDS = {
    "validate-version" => :validate_version,
    "resolve-previous-version" => :resolve_previous_version,
    "read-draft-release" => :read_draft_release,
    "insert-changelog" => :insert_changelog,
    "rewrite-footer" => :rewrite_footer,
    "verify-version" => :verify_version
  }.freeze

  def run(argv)
    command = COMMANDS[argv[0]]
    abort "usage: #{File.basename($PROGRAM_NAME)} {#{COMMANDS.keys.join("|")}}" unless command
    public_send(command)
  end
end

ReleasePrep.run(ARGV)
