# frozen_string_literal: true

require "json"
require "test/unit"

class WriteCommentGuardTest < Test::Unit::TestCase
  SETTINGS = File.expand_path("../settings.json", __dir__)

  def pattern
    hooks = JSON.parse(File.read(SETTINGS)).dig("hooks", "PreToolUse", 0, "hooks")
    command = hooks.find { |h| h["command"].include?("write-comment") }.fetch("command")
    Regexp.new(command[/'([^']*)'\z/, 1])
  end

  def test_matches_guarded_extension_absolute_path
    assert pattern.match?("/Users/t/dd-trace-rb/lib/datadog/tracing/span.rb")
  end

  def test_excludes_vendor_rbs_absolute_path
    refute pattern.match?("/Users/t/dd-trace-rb/vendor/rbs/x.rbs")
  end

  def test_excludes_vendor_rbs_relative_path
    refute pattern.match?("vendor/rbs/x.rbs")
  end

  def test_excludes_gemfiles_absolute_path
    refute pattern.match?("/Users/t/dd-trace-rb/gemfiles/foo.rb")
  end

  def test_does_not_exclude_similarly_named_directory
    assert pattern.match?("/Users/t/dd-trace-rb/vendor/rbs-extra/x.rbs")
  end
end
