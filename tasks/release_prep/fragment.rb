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
      errors
    end
  end
end
