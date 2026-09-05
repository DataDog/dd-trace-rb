# frozen_string_literal: true

require "json"
require_relative "../release_prep"

# One changelog fragment file (unreleased/*.json): the unit of changelog-worthy
# change that a pull request commits alongside its code.
module ReleasePrep
  class Fragment
    TYPES = %w[Added Changed Fixed].freeze
    MESSAGE_LENGTH_CAP = 240
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

    # Customer-facing product names whose casing a changelog message must get
    # right; a lowercase form is a misspelling, not a style preference.
    CANONICAL_CASING = {
      "appsec" => "AppSec",
      "opentelemetry" => "OpenTelemetry",
      "otel" => "OTel",
    }.freeze

    # The renderer appends "(#NNNN)" from the pull_request field, so a PR
    # reference inside the message is either a duplicate of that tail or an
    # internal pointer customers have no use for.
    PR_REFERENCES = /#\d+|\b(?:PR|pull request)\b/i.freeze

    MESSAGE_SENTENCE_CAP = 3

    attr_reader :path, :type, :prefix, :pull_request, :message, :author

    def self.read(path)
      entry = JSON.parse(File.read(path))
      new(path, entry)
    rescue JSON::ParserError => e
      raise ValidationError, "#{path}: invalid JSON (#{e.message})"
    end

    def initialize(path, entry)
      @path = path
      @entry = entry
      @type = entry["type"]
      @prefix = entry["prefix"]
      @pull_request = entry["pull_request"]
      @message = entry["message"]
      @author = entry["author"]
    end

    def pr_number
      pull_request.split("/").last
    end

    def to_s
      credit = author ? " (@#{author})" : ""
      "* #{prefix}: #{message} (##{pr_number})#{credit}"
    end

    def delete!
      File.delete(path)
    end

    # Every violation this fragment carries, not just the first: callers
    # report the full list in one pass (see ReleasePrep.validate_fragments!).
    def errors
      errors = []
      REQUIRED_FIELDS.each do |field|
        errors << "#{path}: missing required field #{field.inspect}" if @entry[field].to_s == ""
      end
      errors << "#{path}: type #{@type.inspect} must be one of #{TYPES.inspect}" unless TYPES.include?(@type)
      errors << "#{path}: prefix #{@prefix.inspect} must be one of #{PREFIXES.inspect}" unless PREFIXES.include?(@prefix)
      unless pull_request.to_s.match?(%r{\Ahttps://github\.com/DataDog/dd-trace-rb/pull/\d+\z})
        errors << "#{path}: pull_request must be a https://github.com/DataDog/dd-trace-rb/pull/NNNN URL " \
          "(got #{@pull_request.inspect})"
      end
      if message.to_s.length > MESSAGE_LENGTH_CAP
        errors << "#{path}: message is #{message.length} characters, cap is #{MESSAGE_LENGTH_CAP}"
      end
      prose = without_code_spans(message.to_s)
      CANONICAL_CASING.each do |term, canonical|
        if prose.match?(%r{\b#{Regexp.escape(term)}\b})
          errors << "#{path}: message uses #{term.inspect}; write it as #{canonical.inspect}"
        end
      end
      backticks = message.to_s.count("`")
      if backticks.odd?
        errors << "#{path}: message has #{backticks} backticks; code spans need an even number"
      end
      errors << "#{path}: message has an empty code span" if message.to_s.include?("``")
      count = sentence_count(message.to_s)
      if count > MESSAGE_SENTENCE_CAP
        errors << "#{path}: message has #{count} sentences, cap is #{MESSAGE_SENTENCE_CAP}"
      end
      if (reference = message.to_s[PR_REFERENCES])
        errors << "#{path}: message references #{reference.inspect}; the PR number is rendered " \
          "automatically from the pull_request field"
      end
      errors
    end

    private

    # Code spans name identifiers whose casing and punctuation the code itself
    # fixes (e.g. `appsec.track_user_events`), so checks about prose never see
    # inside them.
    def without_code_spans(text)
      text.gsub(/`[^`]*`/, "")
    end

    # ., !, or ? followed by whitespace or end of text delimits sentences;
    # code spans are stripped and e.g./i.e. neutralized first, so paths and
    # version numbers inside `code` never split a message that is one sentence.
    def sentence_count(text)
      without_code_spans(text).gsub(/\b(?:e\.g|i\.e)\./i, "").scan(/[.!?]+(?=\s|\z)/).size
    end
  end
end
