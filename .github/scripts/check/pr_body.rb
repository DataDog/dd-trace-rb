#!/usr/bin/env ruby
# frozen_string_literal: true

# CI check for the pull request description, run from check.yml.
# Enforces the required PR body fields (### Why, ### What, ### Risk) and
# their caps. Drafts are included: the body is expected to be complete
# when the PR is opened.

require "set"

MAX_WORDS = 50
MAX_SENTENCES = 2
REQUIRED_FIELDS = ["Why", "What", "Risk"].freeze
OPTIONAL_FIELDS = ["Details"].freeze

body = ENV["PR_BODY"] || ""

# HTML comments are guidance, not content.
stripped = body.gsub(/<!--.*?-->/m, "")

sections = {}
current = nil
stripped.each_line do |line|
  if (match = line.match(/\A###\s+(\S+)\s*\z/))
    current = match[1]
    sections[current] = +""
  elsif current
    sections[current] << line
  end
end

failures = []

present = sections.keys.to_set
REQUIRED_FIELDS.each do |field|
  unless present.include?(field)
    failures << "missing required field '### #{field}'"
    next
  end

  content = sections[field].strip
  failures << "field '### #{field}' is empty" if content.empty?

  words = content.split
  if words.size > MAX_WORDS
    failures << "'### #{field}' has #{words.size} words (max #{MAX_WORDS})"
  end

  sentences = content.split(/[.!?]+(?=\s|\z)/).reject { |sentence| sentence.strip.empty? }
  if sentences.size > MAX_SENTENCES
    failures << "'### #{field}' has #{sentences.size} sentences (max #{MAX_SENTENCES})"
  end

  # A markdown link's URL is optional context. A bare URL is not a sentence.
  bare_urls = content.gsub(/\[[^\]]*\]\([^)]*\)/, "").scan(%r{https?://\S+})
  unless bare_urls.empty?
    failures << "'### #{field}' has a bare URL. Use markdown link style, or move it to Details"
  end
end

unexpected = present - REQUIRED_FIELDS.to_set - OPTIONAL_FIELDS.to_set
unexpected.each { |field| failures << "unexpected field '### #{field}'" }

if failures.empty?
  puts "PR body OK"
else
  failures.each { |failure| puts "PR body: #{failure}" }
  exit 1
end
