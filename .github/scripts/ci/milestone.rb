# frozen_string_literal: true

require "base64"
require_relative "github"

module CI
  class Milestone
    def self.update(api, repository, number)
      path = "repos/#{repository}"
      pr = api.get("#{path}/pulls/#{Integer(number)}")
      return unless pr["merged"] == true && pr["milestone"].nil?
      return unless pr.dig("base", "repo", "full_name") == repository

      file = api.get("#{path}/contents/lib/datadog/version.rb?ref=#{pr.fetch("merge_commit_sha")}")
      raise "Expected a base64-encoded version file" unless file["type"] == "file" && file["encoding"] == "base64"

      source = Base64.strict_decode64(file.fetch("content").delete("\n"))
      major = source[/^\s*MAJOR\s*=\s*(\d+)\s*$/, 1]
      raise "Could not find a literal major version" unless major

      milestone = api.list("#{path}/milestones?state=open").find { |entry| entry.fetch("title").match?(/\A#{major}(?:\.|$)/) }
      api.request("PATCH", "#{path}/issues/#{Integer(number)}", {milestone: milestone.fetch("number")}) if milestone
    end
  end
end

if $PROGRAM_NAME == __FILE__
  repository, number = ARGV
  CI::Milestone.update(CI::GitHub.new, repository, number)
end
