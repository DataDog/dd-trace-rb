# frozen_string_literal: true

require "date"
require "json"
require "net/http"

if Gem.loaded_specs.key?("pimpmychangelog")
  require "pimpmychangelog"
end

module ReleaseNotes
  REPO = "DataDog/dd-trace-rb"
  REPO_URL = "https://github.com/#{REPO}"
  API_URL = "https://api.github.com"
  CHANGELOG_FILE = "CHANGELOG.md"

  PREVIOUS_VERSION_PATTERN = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/v(.+?)\.\.\.master}
  UNRELEASED_FOOTER_PATTERN = %r{\[Unreleased\]: #{Regexp.escape(REPO_URL)}/compare/.*?\.\.\.master}

  module_function

  def previous_version
    content = File.read(CHANGELOG_FILE)
    match = content.match(PREVIOUS_VERSION_PATTERN)
    fail!("Could not find the [Unreleased] compare link in #{CHANGELOG_FILE}") unless match

    match[1]
  end

  def create_draft_release(version, body)
    uri = URI("#{API_URL}/repos/#{REPO}/releases")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{ENV["GITHUB_TOKEN"]}"
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["User-Agent"] = "dd-trace-rb-release-prep"
    request["Content-Type"] = "application/json"
    request.body = {
      tag_name: "v#{version}",
      name: "v#{version}",
      body: body,
      draft: true,
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    fail!("Failed to create draft release for v#{version}: #{response.code} #{response.body}") unless response.is_a?(Net::HTTPSuccess)

    nil
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

module ReleaseNotes
  module Fragments
    class ValidationError < StandardError; end

    TYPES = %w[Added Changed Fixed].freeze
    PREFIXES = [
      "Core",
      "Tracing",
      "Profiling",
      "AppSec",
      "AI Guard",
      "Dynamic Instrumentation",
      "Data Streams",
      "Error Tracking",
      "Open Feature",
      "OpenTelemetry",
    ].freeze
    REQUIRED_FIELDS = %w[type prefix pull_request message].freeze

    SECTION_ORDER = TYPES

    module_function

    def render(entries, highlights: nil)
      return highlights.to_s if entries.empty?

      sections = SECTION_ORDER.map do |type|
        type_entries = entries.select { |e| e["type"] == type }
        next if type_entries.empty?

        lines = type_entries.sort_by { |e| e["prefix"] }.map { |e| render_line(e) }
        "### #{type}\n\n#{lines.join("\n")}"
      end.compact

      blocks = [highlights, *sections].compact
      body = blocks.join("\n\n")
      pimped = PimpMyChangelog::Pimper.new(*REPO.split("/"), body).better_changelog
      pimped.sub(/\n*\z/, "")
    end

    def render_line(entry)
      pr_number = entry["pull_request"].split("/").last
      credit = entry["author"] ? " (@#{entry["author"]})" : ""
      "* #{entry["prefix"]}: #{entry["message"]} (##{pr_number})#{credit}"
    end
    private_class_method :render_line

    def read_all(dir: "unreleased")
      Dir.glob(File.join(dir, "*.json")).sort.map { |path| read_one(path) }
    end

    def validate_examples!(dir: "unreleased")
      Dir.glob(File.join(dir, "examples", "*.json")).sort.each { |path| read_one(path) }
      nil
    end

    def read_one(path)
      entry = JSON.parse(File.read(path))
      validate!(entry, path)
      entry.merge("_path" => path)
    rescue JSON::ParserError => e
      raise ValidationError, "#{path}: invalid JSON (#{e.message})"
    end

    def validate!(entry, path)
      REQUIRED_FIELDS.each do |field|
        next if entry[field].to_s != ""

        raise ValidationError, "#{path}: missing required field #{field.inspect}"
      end

      unless TYPES.include?(entry["type"])
        raise ValidationError, "#{path}: type #{entry["type"].inspect} must be one of #{TYPES.inspect}"
      end

      unless PREFIXES.include?(entry["prefix"])
        raise ValidationError, "#{path}: prefix #{entry["prefix"].inspect} must be one of #{PREFIXES.inspect}"
      end
    end

    def consume!(entries, highlights_path: nil)
      entries.each { |entry| File.delete(entry.fetch("_path")) }
      File.delete(highlights_path) if highlights_path && File.exist?(highlights_path)
      nil
    end
  end
end
