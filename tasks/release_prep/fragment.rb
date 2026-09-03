# frozen_string_literal: true

require "json"
require_relative "../release_prep"

# One changelog fragment file (unreleased/*.json): the unit of changelog-worthy
# change that a pull request commits alongside its code.
module ReleasePrep
  class Fragment
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

    attr_reader :path, :type, :prefix, :pull_request, :message, :author

    def self.read(path)
      entry = JSON.parse(File.read(path))
      validate!(entry, path)
      new(path, entry)
    rescue JSON::ParserError => e
      raise ValidationError, "#{path}: invalid JSON (#{e.message})"
    end

    def initialize(path, entry)
      @path = path
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

    def self.validate!(entry, path)
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
    private_class_method :validate!
  end
end
