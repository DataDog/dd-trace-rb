#!/usr/bin/env ruby
# frozen_string_literal: true

# Nano tool to generate a changelog entry for the current branch in the `changelog/` directory.
#
# Run interactively: `ruby changelog/add.rb`
# Run non-interactively: `ruby changelog/add.rb --category Added --label Profiling --entry "Add Matz conference talks profiling"`
# Run non-interactively with no entry needed: `ruby changelog/add.rb --category None`

require "optparse"

CATEGORIES = ["Added", "Changed", "Fixed", "Removed", "Uncategorized", "None"].freeze
LABELS = [
  "Core",
  "Tracing",
  "Tracing: Integrations",
  "Profiling",
  "AppSec",
  "AI Guard",
  "Dynamic Instrumentation",
  "Data Streams",
  "Error Tracking",
  "OpenFeature",
  "OpenTelemetry",
  "SSI",
  "Uncategorized",
].freeze

def main
  options = {}

  OptionParser.new do |parser|
    parser.banner = "Usage: ruby changelog/add.rb [options]\n" \
      "Example: ruby changelog/add.rb --category Added --label Profiling --entry 'Add Matz conference talks profiling'"
    parser.on("-c", "--category CATEGORY", "One of: #{CATEGORIES.join(", ")}") { |v| options[:category] = v }
    parser.on("-l", "--label LABEL", "One of: #{LABELS.join(", ")}") { |v| options[:label] = v }
    parser.on("-e", "--entry ENTRY", "Short customer-facing sentence describing the change") { |v| options[:entry] = v }
  end.parse!

  puts "Welcome to `changelog/add.rb`. This tool automates generating a changelog entry for the current branch." if options.empty?

  category = options[:category] || prompt("Pick a category:", choices: CATEGORIES)
  abort "Invalid category #{category.inspect}, must be one of: #{CATEGORIES.join(", ")}" unless CATEGORIES.include?(category)

  line =
    if category == "None"
      "* [None] (No changelog entry needed)"
    else
      label = options[:label] || prompt("Pick a label:", choices: LABELS)
      abort "Invalid label #{label.inspect}, must be one of: #{LABELS.join(", ")}" unless LABELS.include?(label)

      entry = options[:entry] || prompt("Enter the changelog entry. This should be a short sentence to be read and understood by customers:")
      abort "Changelog entry cannot be blank" if entry.to_s.strip.empty?
      abort "Changelog entry cannot contain newlines" if entry.include?("\n")

      "* [#{category}] #{label}: #{entry}"
    end

  path = File.join(__dir__, "unreleased-#{sanitized_branch_name}.md")
  already_existed = File.exist?(path)

  File.open(path, "a") { |file| file.puts(line) }

  puts "This file already existed, so the entry has been appended to it." if already_existed
  puts "Done! Saved entry in changelog/#{File.basename(path)} (Remember to `git add` it!)"
end

def prompt(question, choices: nil)
  abort "Missing required option for #{question.inspect} (see --help)." unless $stdin.tty?

  loop do
    print "#{question} "
    print "[#{choices.join(", ")}] " if choices
    answer = $stdin.gets&.strip
    abort "No input received." if answer.nil?
    return answer if choices.nil? || choices.include?(answer)
    puts "Invalid value #{answer.inspect}, must be one of: #{choices.join(", ")}"
  end
end

def sanitized_branch_name
  branch = `git rev-parse --abbrev-ref HEAD`.strip
  abort "Could not detect the current git branch." unless $?.success?
  abort "Could not detect the current git branch, is HEAD detached?" if branch.empty? || branch == "HEAD"

  branch.gsub(/[^a-zA-Z0-9_-]/, ".")
end

main
