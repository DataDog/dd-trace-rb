# frozen_string_literal: true

require 'date'
require 'json'
require 'net/http'

# Release-prep logic for the `release_prep:prepare` task, invoked by
# `.github/workflows/release-prep.yml`.
#
# The version is passed as a task argument, e.g.
#   rake "release_prep:prepare[2.36.0]"
#
# GITHUB_TOKEN (the dd-octo-sts output) is read from the environment to read the
# draft release. The previous version is read from the existing [Unreleased]
# compare link in the changelog, so it does not need to be passed in.
#
# Ports FastCastle's FileEditor.insert_after / FileEditor.replace semantics.
module ReleasePrep
  REPO = 'DataDog/dd-trace-rb'
  REPO_URL = "https://github.com/#{REPO}"
  API_URL = 'https://api.github.com'
  CHANGELOG_FILE = 'CHANGELOG.md'

  # Separates release "highlights" (release-page only) from the changelog body in
  # the draft release. When the marker is absent we fall back to the whole body.
  CHANGELOG_MARKER = '<!-- changelog -->'

  module_function

  # Reject anything that is not MAJOR.MINOR.PATCH with an optional suffix.
  def validate_version!(version)
    fail!("Invalid version '#{version}' (expected e.g. 2.36.0)") unless version.match?(/\A\d+\.\d+\.\d+([._-].+)?\z/)
    puts "Version '#{version}' is valid"
  end

  # The previous released version, read from the existing [Unreleased] compare
  # link (".../compare/vX.Y.Z...master"): before this release, its base is the
  # last release. Capture this before editing the changelog.
  def previous_version
    content = File.read(CHANGELOG_FILE)
    match = content.match(%r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/v(.+?)\.\.\.master})
    fail!("Could not find the [Unreleased] compare link in #{CHANGELOG_FILE}") unless match

    previous = match[1]
    puts "Using previous version: #{previous}"
    previous
  end

  # Fetch the approved draft release for tag vX.Y.Z and return its changelog body.
  def draft_changelog(version)
    uri = URI("#{API_URL}/repos/#{REPO}/releases?per_page=100")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{ENV['GITHUB_TOKEN']}"
    request['Accept'] = 'application/vnd.github+json'
    request['X-GitHub-Api-Version'] = '2022-11-28'
    request['User-Agent'] = 'dd-trace-rb-release-prep'

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    fail!("GitHub API request failed: #{response.code} #{response.body}") unless response.is_a?(Net::HTTPSuccess)

    tag = "v#{version}"
    draft = JSON.parse(response.body).find { |release| release['tag_name'] == tag && release['draft'] == true }
    fail!("No draft release found with tag #{tag}. Please create and approve a draft release first.") unless draft

    body = draft['body'].to_s
    puts "Read draft release body for #{tag} (#{body.length} chars)"

    # Highlights (release-page only) precede the marker; the changelog follows
    # it. Fall back to the whole body when the marker is absent.
    changelog = body.include?(CHANGELOG_MARKER) ? body.split(CHANGELOG_MARKER, 2).last : body
    changelog.strip
  end

  # Insert the new "## [X.Y.Z] - <date>" section right after the [Unreleased] marker.
  def insert_changelog(version, changelog)
    content = File.read(CHANGELOG_FILE)
    match = content.match(/\[Unreleased\]/)
    fail!("Could not find [Unreleased] marker in #{CHANGELOG_FILE}") unless match

    section = "\n## [#{version}] - #{Date.today}\n\n#{changelog}".rstrip
    File.write(CHANGELOG_FILE, content.insert(match.end(0), "\n#{section}"))
  end

  # Rewrite the [Unreleased]/[X.Y.Z] compare links in the changelog footer.
  def rewrite_footer(version, previous)
    pattern = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/.*?\.\.\.master}
    replacement =
      "[Unreleased]: #{REPO_URL}/compare/v#{version}...master\n" \
      "[#{version}]: #{REPO_URL}/compare/v#{previous}...v#{version}"

    content = File.read(CHANGELOG_FILE)
    fail!("Could not find [Unreleased] compare link in #{CHANGELOG_FILE}") unless content.match?(pattern)

    File.write(CHANGELOG_FILE, content.sub(pattern, replacement))
  end

  # Emit a GitHub Actions error annotation and fail the step.
  def fail!(message)
    abort "::error::#{message}"
  end
end

namespace :release_prep do
  desc 'Prepare a release: write the changelog and bump the gem version (e.g. release_prep:prepare[2.36.0])'
  task :prepare, [:version] do |_t, args|
    version = args[:version] || raise(ArgumentError, 'Please provide a version, e.g. rake "release_prep:prepare[2.36.0]"')

    ReleasePrep.validate_version!(version)
    previous = ReleasePrep.previous_version
    changelog = ReleasePrep.draft_changelog(version)

    ReleasePrep.insert_changelog(version, changelog)
    Rake::Task['changelog:format'].invoke
    ReleasePrep.rewrite_footer(version, previous)

    # `version:bump` also asserts the resulting gemspec matches the version.
    Rake::Task['version:bump'].invoke(version)
  end
end
