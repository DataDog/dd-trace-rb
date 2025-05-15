#!/usr/bin/env ruby

# Usage: ruby update_gitlab_ci_ref.rb <file_path> <new_sha>

require 'pry'
class GitlabCiRefUpdater
  def initialize(file_path, new_sha)
    @file_path = file_path
    @new_sha = new_sha
    @updated = false
  end

  def update
    # Read the file content
    content = File.read(@file_path)

    # Split into lines for processing
    lines = content.split("\n")
    # Find and replace lines with the pattern "ref: <sha> # YOGA: ..." (with any indentation)
    lines.map! do |line|
      if line.match?(/^\s*ref:.*# YOGA:/)
        @updated = true
        # Keep everything before the SHA, replace the SHA, and keep everything after
        line.sub(/(\s*ref:\s*)([0-9a-f]+)(\s*# YOGA:.*)/, "\\1#{@new_sha}\\3")
      else
        line
      end
    end

    # Only write back if changes were made
    if @updated
      File.write(@file_path, lines.join("\n"))
      puts "Successfully updated SHA reference in #{@file_path}"
    else
      puts "No matching references found in #{@file_path}"
    end

    @updated
  end
end

# When run as a script
if __FILE__ == $PROGRAM_NAME
  if ARGV.size < 2
    puts "Usage: ruby update_gitlab_ci_ref.rb <file_path> <new_sha>"
    exit 1
  end

  file_path = ARGV[0]
  new_sha = ARGV[1]

  updater = GitlabCiRefUpdater.new(file_path, new_sha)
  success = updater.update

  exit(success ? 0 : 1)
end
