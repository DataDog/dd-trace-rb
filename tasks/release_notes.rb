# frozen_string_literal: true

require "date"
require "json"
require "net/http"

module ReleaseNotes
  REPO = "DataDog/dd-trace-rb"
  REPO_URL = "https://github.com/#{REPO}"
  API_URL = "https://api.github.com"
  CHANGELOG_FILE = "CHANGELOG.md"

  # Separates release "highlights" (release-page only) from the changelog body in
  # the draft release. When the marker is absent we fall back to the whole body.
  CHANGELOG_MARKER = "<!-- changelog -->"

  PREVIOUS_VERSION_PATTERN = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/v(.+?)\.\.\.master}
  UNRELEASED_FOOTER_PATTERN = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/.*?\.\.\.master}

  module_function

  def previous_version
    content = File.read(CHANGELOG_FILE)
    match = content.match(PREVIOUS_VERSION_PATTERN)
    fail!("Could not find the [Unreleased] compare link in #{CHANGELOG_FILE}") unless match

    match[1]
  end

  def draft_changelog(version)
    uri = URI("#{API_URL}/repos/#{REPO}/releases?per_page=100")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{ENV["GITHUB_TOKEN"]}"
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["User-Agent"] = "dd-trace-rb-release-prep"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    fail!("GitHub API request failed: #{response.code} #{response.body}") unless response.is_a?(Net::HTTPSuccess)

    tag = "v#{version}"
    draft = JSON.parse(response.body).find { |release| release["tag_name"] == tag && release["draft"] == true }
    fail!("No draft release found with tag #{tag}. Please create and approve a draft release first.") unless draft

    # GitHub's API intermittently returns release bodies with CRLF line endings.
    # Normalize to LF so we don't pollute CHANGELOG.md with mixed line endings.
    body = draft["body"].to_s.gsub(/\r\n?/, "\n")

    # Highlights (release-page only) precede the marker; the changelog follows
    # it. Fall back to the whole body when the marker is absent.
    changelog = body.include?(CHANGELOG_MARKER) ? body.split(CHANGELOG_MARKER, 2).last : body
    changelog.strip
  end

  def insert_changelog(version, changelog)
    content = File.read(CHANGELOG_FILE)
    match = content.match(/\[Unreleased\]/)
    fail!("Could not find [Unreleased] marker in #{CHANGELOG_FILE}") unless match

    section = "\n## [#{version}] - #{Date.today}\n\n#{changelog}".rstrip
    File.write(CHANGELOG_FILE, content.insert(match.end(0), "\n#{section}"))
  end

  def rewrite_footer(version, previous)
    pattern = UNRELEASED_FOOTER_PATTERN
    replacement =
      "[Unreleased]: #{REPO_URL}/compare/v#{version}...master\n" \
      "[#{version}]: #{REPO_URL}/compare/v#{previous}...v#{version}"

    content = File.read(CHANGELOG_FILE)
    fail!("Could not find [Unreleased] compare link in #{CHANGELOG_FILE}") unless content.match?(pattern)

    File.write(CHANGELOG_FILE, content.sub(pattern, replacement))
  end

  def fail!(message)
    abort "::error::#{message}"
  end
end
