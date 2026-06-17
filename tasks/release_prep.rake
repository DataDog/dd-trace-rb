# frozen_string_literal: true

require 'date'
require 'json'
require 'net/http'

# Release-prep logic for the `release_prep:prepare` task, invoked by
# `.github/workflows/release-prep.yml`.
#
# Inputs come from the standard GitHub Actions environment:
#   VERSION           release version, no "v" prefix (e.g. "2.36.0")          [required]
#   PREVIOUS_VERSION  previous released version (optional; defaults to latest v* tag)
#   GITHUB_TOKEN      token used to read the draft release (dd-octo-sts output)
#   GITHUB_REPOSITORY / GITHUB_SERVER_URL / GITHUB_API_URL  provided by Actions
#
# Ports FastCastle's FileEditor.insert_after / FileEditor.replace semantics.
module ReleasePrep
  # Separates release "highlights" (release-page only) from the changelog body in
  # the draft release. When the marker is absent we fall back to the whole body.
  CHANGELOG_MARKER = '<!-- changelog -->'

  module_function

  # Reject anything that is not MAJOR.MINOR.PATCH with an optional suffix.
  def validate_version!
    fail!("Invalid version '#{version}' (expected e.g. 2.36.0)") unless version.match?(/\A\d+\.\d+\.\d+([._-].+)?\z/)
    puts "Version '#{version}' is valid"
  end

  # The explicit input when given, otherwise the latest v* tag.
  def previous_version
    previous = ENV['PREVIOUS_VERSION'].to_s.strip
    if previous.empty?
      tags = `git tag --list 'v*' --sort=-version:refname`.lines.map(&:strip).reject(&:empty?)
      previous = tags.first.to_s.sub(/\Av/, '')
    end
    fail!('Could not determine previous version (no v* tags found); pass previous_version explicitly') if previous.empty?

    puts "Using previous version: #{previous}"
    previous
  end

  # Fetch the approved draft release for tag vX.Y.Z and return its changelog body.
  def draft_changelog
    tag = "v#{version}"
    draft = releases.find { |release| release['tag_name'] == tag && release['draft'] == true }
    fail!("No draft release found with tag #{tag}. Please create and approve a draft release first.") unless draft

    body = draft['body'].to_s
    puts "Read draft release body for #{tag} (#{body.length} chars)"
    extract_changelog(body)
  end

  # Insert the new "## [X.Y.Z] - <date>" section right after the [Unreleased] marker.
  def insert_changelog(changelog)
    content = File.read(changelog_file)
    match = content.match(/\[Unreleased\]/)
    fail!("Could not find [Unreleased] marker in #{changelog_file}") unless match

    section = "\n## [#{version}] - #{Date.today}\n\n#{changelog}".rstrip
    File.write(changelog_file, content.insert(match.end(0), "\n#{section}"))
  end

  # Rewrite the [Unreleased]/[X.Y.Z] compare links in the changelog footer.
  def rewrite_footer(previous)
    pattern = %r{\[Unreleased\]: #{Regexp.escape(repo_url)}/compare/.*?\.\.\.master}
    replacement =
      "[Unreleased]: #{repo_url}/compare/v#{version}...master\n" \
      "[#{version}]: #{repo_url}/compare/v#{previous}...v#{version}"

    content = File.read(changelog_file)
    fail!("Could not find [Unreleased] compare link in #{changelog_file}") unless content.match?(pattern)

    File.write(changelog_file, content.sub(pattern, replacement))
  end

  def extract_changelog(body)
    section = body.include?(CHANGELOG_MARKER) ? body.split(CHANGELOG_MARKER, 2).last : body
    section.strip
  end

  def releases
    uri = URI("#{api_url}/repos/#{repo_slug}/releases?per_page=100")

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{require_env('GITHUB_TOKEN')}"
    request['Accept'] = 'application/vnd.github+json'
    request['X-GitHub-Api-Version'] = '2022-11-28'
    request['User-Agent'] = 'dd-trace-rb-release-prep'

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    fail!("GitHub API request failed: #{response.code} #{response.body}") unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  # --- GitHub Actions environment -------------------------------------------

  def version
    require_env('VERSION')
  end

  def changelog_file
    ENV.fetch('CHANGELOG_FILE', 'CHANGELOG.md')
  end

  def repo_slug
    ENV.fetch('GITHUB_REPOSITORY', 'DataDog/dd-trace-rb')
  end

  def repo_url
    "#{ENV.fetch('GITHUB_SERVER_URL', 'https://github.com')}/#{repo_slug}"
  end

  def api_url
    ENV.fetch('GITHUB_API_URL', 'https://api.github.com')
  end

  def require_env(name)
    value = ENV[name].to_s
    fail!("Missing required environment variable #{name}") if value.empty?
    value
  end

  # Emit a GitHub Actions error annotation and fail the step.
  def fail!(message)
    abort "::error::#{message}"
  end
end

namespace :release_prep do
  desc 'Prepare a release: write the changelog, integration versions, and version bump'
  task :prepare do
    ReleasePrep.validate_version!
    previous = ReleasePrep.previous_version
    changelog = ReleasePrep.draft_changelog

    ReleasePrep.insert_changelog(changelog)
    Rake::Task['changelog:format'].invoke
    ReleasePrep.rewrite_footer(previous)

    sh 'bundle exec ruby .github/scripts/update_supported_versions.rb'

    # `version:bump` also asserts the resulting gemspec matches the version.
    Rake::Task['version:bump'].invoke(ReleasePrep.version)
  end
end
