#!/usr/bin/env ruby

# frozen_string_literal: true

require "optparse"
require "open3"

module SystemTests
  Decision = Struct.new(:file, :groups, :reason)
  Selection = Struct.new(:groups, :decisions, :full_suite)

  class Selector
    FULL_SUITE = "tracer_release"

    RULES = [
      ["ai_guard", [%r{\Alib/datadog/ai_guard/}], "AI Guard product code"],
      ["appsec", [%r{\Alib/datadog/appsec/}, %r{\Alib/datadog/kit/appsec/}], "AppSec product code"],
      ["debugger", [%r{\Alib/datadog/di/}, %r{\Alib/datadog/symbol_database/}], "Dynamic Instrumentation product code"],
      ["ffe", [%r{\Alib/datadog/open_feature/}], "OpenFeature product code"],
      ["open_telemetry", [%r{\Alib/datadog/opentelemetry/}], "OpenTelemetry bridge code"],
      [
        "profiling",
        [%r{\Alib/datadog/profiling/}, %r{\Aext/datadog_profiling_native_extension/}],
        "profiling product code",
      ],
      ["remote_config", [%r{\Alib/datadog/core/remote/}], "remote configuration code"],
      ["sampling", [%r{\Alib/datadog/tracing/sampling/}], "trace sampling code"],
      ["telemetry", [%r{\Alib/datadog/core/telemetry/}], "telemetry code"],
      ["tracing_config", [%r{\Alib/datadog/tracing/configuration/}], "tracing configuration code"],
    ].freeze

    def initialize(changed_files)
      @changed_files = changed_files
    end

    def call
      decisions = @changed_files.sort.map { |file| classify(file) }
      full_suite = decisions.empty? || decisions.any? { |decision| decision.groups.include?(FULL_SUITE) }
      groups = if full_suite
        [FULL_SUITE]
      else
        decisions.flat_map(&:groups).uniq.sort
      end

      Selection.new(groups, decisions, full_suite)
    end

    private

    def classify(file)
      rule = RULES.find do |_group, patterns, _reason|
        patterns.any? { |pattern| pattern.match?(file) }
      end

      return Decision.new(file, [rule[0]], rule[2]) if rule

      Decision.new(file, [FULL_SUITE], "shared or unclassified code")
    end
  end

  class Report
    def initialize(selection)
      @selection = selection
    end

    def to_markdown
      lines = [
        "## Smart system-tests selection (shadow mode)",
        "",
        "This recommendation does not change the system-tests executed by this workflow.",
        "",
        "**Recommended scenario groups:** `#{@selection.groups.join(",")}`",
        "",
      ]

      if @selection.decisions.empty?
        lines << "No changed files were found, so the conservative full-suite fallback was selected."
        return lines.join("\n")
      end

      lines.concat([
        "| Changed file | Recommendation | Reason |",
        "| --- | --- | --- |",
      ])
      @selection.decisions.each do |decision|
        lines << "| `#{escape(decision.file)}` | `#{decision.groups.join(",")}` | #{escape(decision.reason)} |"
      end
      lines << ""
      lines << fallback_summary
      lines.join("\n")
    end

    private

    def escape(value)
      value.to_s.gsub("|", "\\|")
    end

    def fallback_summary
      if @selection.full_suite
        "At least one change was not safely isolated, so the recommendation fails open to `tracer_release`."
      else
        "Every change was isolated to a known product area."
      end
    end
  end

  class CLI
    def self.run(arguments)
      options = {head: "HEAD"}
      OptionParser.new do |parser|
        parser.on("--base SHA") { |value| options[:base] = value }
        parser.on("--head SHA") { |value| options[:head] = value }
      end.parse!(arguments)

      raise OptionParser::MissingArgument, "--base" unless options[:base]

      stdout, stderr, status = Open3.capture3(
        "git",
        "diff",
        "--name-only",
        "--diff-filter=ACDMRTUXB",
        "#{options[:base]}...#{options[:head]}",
      )
      raise "Unable to inspect changed files: #{stderr}" unless status.success?

      files = stdout.lines.map(&:strip).reject(&:empty?)
      puts Report.new(Selector.new(files).call).to_markdown
    end
  end
end

SystemTests::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
