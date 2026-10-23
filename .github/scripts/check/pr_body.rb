#!/usr/bin/env ruby
# frozen_string_literal: true

# CI check for the pull request description, run from check.yml.
# Enforces the required PR body fields (### Why, ### What, ### Risk) and
# their caps. Drafts are included: the body is expected to be complete
# when the PR is opened. A `<!-- pr-body: skip -->` comment opts a body
# out. check.yml names who is exempt without it.
#
# Run `ruby .github/scripts/check/pr_body.rb --self-test` to verify the
# counting logic.

MAX_WORDS = 50
MAX_SENTENCES = 2
SKIP_MARKER = "<!-- pr-body: skip -->"
# Quotes only matter inside quoted attribute values, and no sink places
# findings inside one. Escaping them garbles every failure line.
HTML_CONTEXT = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }.freeze
REQUIRED_FIELDS = ["Why", "What", "Risk"].freeze
OPTIONAL_FIELDS = ["Details"].freeze

# A period can appear without ending a sentence: inside code spans, in an
# ellipsis, or as part of a common abbreviation. None of those split.
def sentence_count(content)
  text = content.gsub(/`[^`]*`/, "code")
    .gsub(/\.{3,}/, "\u2026")
    .gsub(/\b(?:e\.g|i\.e|etc|vs|approx|Mr|Mrs|Dr|Inc|Ltd)\./, "abbr")
  text.split(/[.!?]+["')\]]*(?=\s|\z)/).count { |sentence| !sentence.strip.empty? }
end

# Neutralize every character that can open an HTML context in the output.
def html_neutral(text)
  text.gsub(/[&<>]/, HTML_CONTEXT)
end

def check_body(body)
  return [] if body.include?(SKIP_MARKER)

  # HTML comments are guidance, not content.
  stripped = body.gsub(/<!--.*?-->/m, "")

  sections = {}
  current = nil
  stripped.each_line do |line|
    if (match = line.match(/\A###\s+(\S+)\s*\z/))
      current = match[1]
      return ["duplicate field '### #{current}'"] if sections.key?(current)
      sections[current] = +""
    elsif current
      sections[current] << line
    end
  end

  failures = []
  present = sections.keys

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

    sentences = sentence_count(content)
    if sentences > MAX_SENTENCES
      failures << "'### #{field}' has #{sentences} sentences (max #{MAX_SENTENCES})"
    end

    # A markdown link's URL is optional context. A bare URL is not a sentence.
    bare_urls = content.gsub(/\[[^\]]*\]\([^)]*\)/, "").scan(%r{https?://\S+})
    unless bare_urls.empty?
      failures << "'### #{field}' has a bare URL. Use markdown link style, or move it to Details"
    end
  end

  unexpected = present - REQUIRED_FIELDS - OPTIONAL_FIELDS
  unexpected.each { |field| failures << "unexpected field '### #{field}'" }

  failures
end

def self_test
  cases = {
    "two plain sentences" => ["One sentence. Two sentences.", 2],
    "version numbers do not split" => ["Bumps datadog to v2.47.0. Fixes the bug.", 2],
    "decimals do not split" => ["Cuts overhead by 50.5 percent. Scoped.", 2],
    "e.g. does not split" => ["Fixes failures, e.g. crashes, on Rails 7. Two-way door.", 2],
    "code spans do not split" => ["The clock in `serializer.rb` reads CPU time. Revert.", 2],
    "sentence ends inside quotes" => ["He said \"stop.\" Then we merged.", 2],
    "sentence ends inside parens" => ["(See the docs.) Then it worked.", 2],
    "closing quote at field end" => ["He said \"merge it.\"", 1],
    "closing paren at field end" => ["Scoped to DI. (Revert restores the old clock.)", 2],
    "ellipsis does not split" => ["Wait... then merge. Two-way door.", 2],
    "three real sentences" => ["One. Two. Three.", 3],
    "empty content" => ["", 0],
  }
  failed = 0
  cases.each do |name, (content, expected)|
    actual = sentence_count(content)
    next if actual == expected

    puts "self-test failed: #{name}: expected #{expected}, got #{actual}"
    failed += 1
  end

  # Body fixtures: an `<!-- expect: ... -->` header names the finding a
  # body must produce, or is empty when the body must pass. The header is
  # a comment, so check_body treats the rest as the body under test.
  fixtures = Dir.glob(File.expand_path("fixtures", __dir__) + "/*.md").sort
  fixtures.each do |path|
    content = File.read(path)
    expected = content[/\A<!--\s*expect:(.*?)-->/m, 1].to_s.strip
    findings = check_body(content)
    ok = expected.empty? ? findings.empty? : findings.any? { |finding| finding.include?(expected) }
    next if ok

    puts "self-test failed: #{File.basename(path)}: " \
      "expected #{expected.empty? ? "no findings" : "'#{expected}'"}, got #{findings.inspect}"
    failed += 1
  end
  total = cases.size + fixtures.size
  abort("self-test: #{failed} of #{total} cases failed") if failed > 0
  puts "self-test OK: #{cases.size} sentence cases, #{fixtures.size} body fixtures"
end

if ARGV.first == "--self-test"
  self_test
  exit
end

failures = check_body(ENV["PR_BODY"] || "")
if failures.empty?
  puts "PR body OK"
else
  claim = "PR body: the description breaks the contract."
  fix = "Fix: fill ### Why, ### What, and ### Risk per .github/PULL_REQUEST_TEMPLATE.md, at most 2 sentences and 50 words each."
  findings = failures.map { |failure| html_neutral(failure) }.join(" ")

  # One annotation carries the claim, the fix, and every finding: the
  # workflow command is a single line, so CI output aggregates while local
  # output stays readable.
  if ENV["GITHUB_ACTIONS"] == "true"
    puts "::error ::#{[claim, fix, findings].join(' ')}"
  else
    puts claim
    puts fix
    puts ""
    failures.each { |failure| puts " - #{html_neutral(failure)}" }
  end
  exit 1
end
