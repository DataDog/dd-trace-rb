# frozen_string_literal: true

require 'date'
require 'json'
require 'net/http'
require 'tmpdir'

# Release-prep steps invoked by `.github/workflows/release-prep.yml`.
#
# Each rake task is one workflow step. Inputs come from the standard GitHub
# Actions environment (VERSION, PREVIOUS_VERSION, GITHUB_*, RUNNER_TEMP), so the
# workflow stays declarative and the same tasks can be run locally by exporting
# those variables.
#
# Run order (the footer is rewritten *after* `changelog:format`, otherwise
# pimpmychangelog reformats the line out from under the rewrite):
#
#   rake release_prep:validate_version
#   rake release_prep:resolve_previous_version
#   rake release_prep:read_draft_release
#   rake release_prep:insert_changelog
#   rake changelog:format
#   rake release_prep:rewrite_footer
#
# Ports FastCastle's FileEditor.insert_after / FileEditor.replace semantics.
module ReleasePrep
  # Separates release "highlights" (release-page only) from the changelog body in
  # the draft release. When the marker is absent we fall back to the whole body.
  CHANGELOG_MARKER = '<!-- changelog -->'

  module_function

  # Reject anything that is not MAJOR.MINOR.PATCH with an optional suffix.
  def validate_version
    fail!("Invalid version '#{version}' (expected e.g. 2.36.0)") unless version.match?(/\A\d+\.\d+\.\d+([._-].+)?\z/)
    puts "Version '#{version}' is valid"
  end

  # Use the explicit input when given, otherwise the latest v* tag. Exported via
  # $GITHUB_ENV so the footer step can read it.
  def resolve_previous_version
    previous = ENV['PREVIOUS_VERSION'].to_s.strip
    if previous.empty?
      tags = `git tag --list 'v*' --sort=-version:refname`.lines.map(&:strip).reject(&:empty?)
      previous = tags.first.to_s.sub(/\Av/, '')
    end
    fail!('Could not determine previous version (no v* tags found); pass previous_version explicitly') if previous.empty?

    puts "Using previous version: #{previous}"
    export_env('PREVIOUS_VERSION', previous)
  end

  # Fetch the approved draft release body for tag vX.Y.Z and write it to RUNNER_TEMP.
  def read_draft_release
    tag = "v#{version}"
    draft = releases.find { |release| release['tag_name'] == tag && release['draft'] == true }
    fail!("No draft release found with tag #{tag}. Please create and approve a draft release first.") unless draft

    body = draft['body'].to_s
    File.write(body_file, body)
    puts "Wrote draft release body for #{tag} (#{body.length} chars)"
  end

  # Insert the new "## [X.Y.Z] - <date>" section right after the [Unreleased] marker.
  def insert_changelog
    changelog = extract_changelog(File.read(body_file))

    content = File.read(changelog_file)
    match = content.match(/\[Unreleased\]/)
    fail!("Could not find [Unreleased] marker in #{changelog_file}") unless match

    section = "\n## [#{version}] - #{Date.today}\n\n#{changelog}".rstrip
    File.write(changelog_file, content.insert(match.end(0), "\n#{section}"))
  end

  # Rewrite the [Unreleased]/[X.Y.Z] compare links in the changelog footer.
  def rewrite_footer
    previous = require_env('PREVIOUS_VERSION')
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

  def body_file
    File.join(ENV.fetch('RUNNER_TEMP', Dir.tmpdir), 'release_body.md')
  end

  # Persist a value for later workflow steps via $GITHUB_ENV (no-op when unset).
  def export_env(name, value)
    github_env = ENV['GITHUB_ENV'].to_s
    return if github_env.empty?

    File.open(github_env, 'a') { |f| f.puts("#{name}=#{value}") }
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
  desc 'Validate the VERSION input'
  task :validate_version do
    ReleasePrep.validate_version
  end

  desc 'Resolve the previous version and export it to $GITHUB_ENV'
  task :resolve_previous_version do
    ReleasePrep.resolve_previous_version
  end

  desc 'Read the approved draft release body into RUNNER_TEMP'
  task :read_draft_release do
    ReleasePrep.read_draft_release
  end

  desc 'Insert the new version section into CHANGELOG.md'
  task :insert_changelog do
    ReleasePrep.insert_changelog
  end

  desc 'Rewrite the CHANGELOG.md compare-link footer'
  task :rewrite_footer do
    ReleasePrep.rewrite_footer
  end
end
