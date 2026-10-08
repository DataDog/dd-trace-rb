# frozen_string_literal: true

require "json"
require "open3"
require "tempfile"
require "test/unit"

require_relative "require-skill"

module SkillEvent
  module_function

  def build(name)
    JSON.generate(
      "message" => {
        "content" => [
          {"type" => "tool_use", "name" => "Skill", "input" => {"skill" => name}},
        ],
      },
    ) + "\n"
  end
end

class SkillTest < Test::Unit::TestCase
  def skill
    Skill.new("write-rbs")
  end

  def transcript(contents)
    file = Tempfile.new("transcript")
    file.write(contents)
    file.close
    yield file.path
  ensure
    file&.unlink
  end

  def test_loaded_when_skill_invoked
    transcript(SkillEvent.build("write-rbs")) do |path|
      assert skill.loaded?(path)
    end
  end

  def test_not_loaded_when_absent
    transcript("nothing relevant here\n") do |path|
      refute skill.loaded?(path)
    end
  end

  def test_mention_in_prose_does_not_satisfy_requirement
    transcript(%({"message":{"content":[{"type":"text","text":"use the write-rbs skill"}]}}\n)) do |path|
      refute skill.loaded?(path)
    end
  end

  def test_prefixed_skill_name_does_not_satisfy_requirement
    transcript(SkillEvent.build("something-write-rbs")) do |path|
      refute skill.loaded?(path)
    end
  end

  def test_suffixed_skill_name_does_not_satisfy_requirement
    transcript(SkillEvent.build("write-rbs-something")) do |path|
      refute skill.loaded?(path)
    end
  end

  def test_not_loaded_when_transcript_missing
    refute skill.loaded?("/no/such")
    refute skill.loaded?(nil)
  end
end

# ==============================================================================
# The compiled binary must match CRuby (the oracle) on every scenario          #
#                                                                              #
# Runs CRuby-only with a warning when no binary is present,                    #
# so the coverage gap stays visible                                            #
# ==============================================================================

class SmokeTest < Test::Unit::TestCase
  HOOK = File.expand_path("require-skill.rb", __dir__)
  BINARY = File.expand_path("compiled/require-skill", __dir__)
  GUARD_ARGV = ["write-rbs", 'sig/.*\.rbs$|vendor/rbs/.*\.rbs$'].freeze

  RUNNERS = {"cruby" => ["ruby", "--disable-gems", HOOK]}
  RUNNERS["binary"] = [BINARY] if File.executable?(BINARY)

  SCENARIOS = [
    {name: "deny_skill_absent", file_path: "sig/x.rbs"},
    {name: "allow_path_no_match", file_path: "lib/x.rb"},
    {name: "allow_skill_loaded", file_path: "sig/x.rbs", transcript: SkillEvent.build("write-rbs")},
    {name: "collision_prefixed_skill", file_path: "sig/x.rbs", transcript: SkillEvent.build("local-write-rbs")},
    {name: "fail_open_garbage_stdin", raw_stdin: "not json at all", compare: :shape},
    {name: "regex_boundary_suffixed", file_path: "sig/x.rbs", transcript: SkillEvent.build("write-rbs-x")},
    {name: "unicode_transcript", file_path: "sig/x.rbs", transcript: %({"message":{"content":[{"type":"text","text":"日本語 write-rbs café"}]}}\n)},
    {name: "mixed_jsonl", file_path: "sig/x.rbs", transcript: "not json\n" + SkillEvent.build("write-rbs")},
  ].freeze

  def setup
    @tmp = []
  end

  def teardown
    @tmp.each(&:unlink)
  end

  def transcript_path(content)
    return "/no/such/transcript" if content.nil?

    file = Tempfile.new("transcript")
    file.write(content)
    file.close
    @tmp << file
    file.path
  end

  def stdin_for(scenario)
    return scenario[:raw_stdin] if scenario[:raw_stdin]

    JSON.generate(
      "tool_input" => {"file_path" => scenario[:file_path]},
      "transcript_path" => transcript_path(scenario[:transcript]),
    )
  end

  def invoke(cmd, stdin)
    Open3.capture2(*cmd, stdin_data: stdin)
  end

  def parse(stdout)
    JSON.parse(stdout)
  rescue JSON::ParserError
    stdout
  end

  def json_keys(stdout)
    parsed = parse(stdout)
    parsed.is_a?(Hash) ? parsed.keys.sort : parsed
  end

  def outputs_match?(a, b, mode)
    if mode == :shape
      json_keys(a) == json_keys(b)
    else
      parse(a) == parse(b)
    end
  end

  def test_binary_boots
    omit "binary absent" unless RUNNERS.key?("binary")

    stdin = JSON.generate("tool_input" => {"file_path" => "lib/x.rb"})
    _out, status = invoke(RUNNERS["binary"] + GUARD_ARGV, stdin)
    assert status.exitstatus, "binary killed by signal #{status.termsig} — incompatible instructions?"
  end

  def test_binary_matches_cruby
    unless RUNNERS.key?("binary")
      warn "[smoke] binary absent — cruby only"
      omit "binary absent — cruby only"
    end

    SCENARIOS.each do |scenario|
      stdin = stdin_for(scenario)
      cruby_out, cruby_status = invoke(RUNNERS["cruby"] + GUARD_ARGV, stdin)
      binary_out, binary_status = invoke(RUNNERS["binary"] + GUARD_ARGV, stdin)

      mode = scenario.fetch(:compare, :exact)
      assert_equal cruby_status.exitstatus, binary_status.exitstatus, "exit diverged on #{scenario[:name]}"
      assert outputs_match?(cruby_out, binary_out, mode), "stdout diverged on #{scenario[:name]} (compare: #{mode})"
    end
  end
end
