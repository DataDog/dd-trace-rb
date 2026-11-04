# frozen_string_literal: true

require_relative "github"

module CI
  class RequiredChecks
    NAMES = [
      "Build Gem (complete)",
      "CodeQL (complete)",
      "Integration Apps (complete)",
      "Lock Dependencies (complete)",
      "Nix (complete)",
      "Static Analysis (complete)",
      "System Tests (complete)",
      "Test macOS (complete)",
      "Test for memory leaks (complete)",
      "Test YJIT (complete)",
      "Unit Tests (complete)",
    ].freeze

    def self.failures(checks, files)
      expected = NAMES.dup
      if files.any? { |file| [file["filename"], file["previous_filename"]].compact.any? { |path| path.start_with?(".claude/hooks/") } }
        expected << "Claude Hook Tests"
      end

      latest = checks.select { |check| check.dig("app", "slug") == "github-actions" }
        .group_by { |check| check.fetch("name") }
        .transform_values { |runs| runs.max_by { |check| check.fetch("id") } }

      expected.each_with_object([]) do |name, failures|
        check = latest[name]
        next if check && check["status"] == "completed" && check["conclusion"] == "success"

        result = check ? (check["conclusion"] || check.fetch("status")) : "missing"
        failures << "#{name}: #{result}"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  repository, sha, number = ARGV
  api = CI::GitHub.new
  checks = api.list("repos/#{repository}/commits/#{sha}/check-runs", key: "check_runs")
  files = api.list("repos/#{repository}/pulls/#{Integer(number)}/files")
  failures = CI::RequiredChecks.failures(checks, files)
  abort failures.join("\n") unless failures.empty?

  puts "All required validation checks succeeded."
end
