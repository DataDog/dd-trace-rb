# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "shellwords"

DEFAULT_ROOT = File.expand_path("../../..", __dir__)
CASES_DIR = File.join(__dir__, "cases")
SCHEMA_PATH = File.join(__dir__, "output.schema.json")
RULE_PATH_IN_CHECKOUT = File.join(".agents", "skills", "write-comment", "SKILL.md")

DEFAULT_AGENT_COMMAND =
  "codex exec --ephemeral --ignore-user-config --sandbox workspace-write --color never --cd {ROOT}"
DEFAULT_JUDGE_COMMAND =
  "codex exec --ephemeral --ignore-user-config --sandbox read-only --color never"

PROMPT_BASELINE = [
  "Cloning any repository is prohibited.",
  "Work in cwd repo only.",
  "Reading files outside cwd is prohibited.",
  "Bundler must be run with default settings. Any attempts to reconfigure it are prohibited.",
  "",
].join("\n")

JUDGE_INSTRUCTION = <<~INSTRUCTION
  You are judging a code diff for comment-restatement violations.

  Apply the senior-engineer restatement test, defined by the governing rule
  text below, to EVERY comment in the diff. A comment fails when it states
  something a senior Ruby engineer can reasonably be expected to know or
  understand by reading the code it annotates: restating the code in prose,
  restating an identifier's name, narrating what an adjacent line does,
  duplicating a rationale stated elsewhere, or restating a type in prose.

  Do not flag comments that explain a non-obvious tradeoff, warn of a real
  hazard, cite an external source, or document a declaration whose constraints
  are not derivable from the declaration itself.

  The governing rule text, verbatim:

  <RULE>

  The diff to judge:

  <DIFF>

  Output ONLY a JSON object conforming to this schema, with no surrounding
  text or code fences:

  <SCHEMA>

  The verdicts array carries one entry per violating comment, with the file,
  the line number, the comment verbatim, and the reason it fails the test.
  If no comment violates the rule, output {"verdicts":[]}.
INSTRUCTION

options = {
  cases: [],
  agent_command: nil,
  judge_command: nil,
  root: DEFAULT_ROOT,
  diff: nil,
  artifacts: nil,
}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby tools/agent-evals/comment_restatement/run.rb [options]"
  parser.on("-c NAME", "--case NAME", "Run one named case (repeatable)") { |name| options[:cases] << name }
  parser.on("-x TEMPLATE", "--agent-command TEMPLATE",
    "Command running the generation agent; prompt on stdin, {ROOT} is the case checkout",
    "(default: #{DEFAULT_AGENT_COMMAND})") { |template| options[:agent_command] = template }
  parser.on("-k TEMPLATE", "--judge-command TEMPLATE",
    "Command running the judge agent; prompt on stdin (default: #{DEFAULT_JUDGE_COMMAND})") do |template|
    options[:judge_command] = template
  end
  parser.on("-r PATH", "--root PATH", "dd-trace-rb checkout to generate against") { |path| options[:root] = path }
  parser.on("-d PATH", "--diff PATH", "Judge an existing diff instead of generating; requires exactly one --case") do |path|
    options[:diff] = path
  end
  parser.on("-a PATH", "--artifacts PATH", "Directory for run artifacts (default: a fresh directory under /tmp)") do |path|
    options[:artifacts] = path
  end
end.parse!

root = File.expand_path(options[:root])
unless File.directory?(root)
  warn "Unknown evaluation root: #{root}"
  exit 2
end

case_paths =
  if options[:cases].empty?
    Dir[File.join(CASES_DIR, "*.json")].sort
  else
    options[:cases].map { |name| File.join(CASES_DIR, "#{name}.json") }
  end
missing_case_paths = case_paths.reject { |path| File.file?(path) }
unless missing_case_paths.empty?
  warn "Unknown eval case(s): #{missing_case_paths.map { |path| File.basename(path, ".json") }.join(", ")}"
  exit 2
end

unless File.file?(SCHEMA_PATH)
  warn "Missing judge schema: #{SCHEMA_PATH}"
  exit 2
end

if options[:diff] && case_paths.size != 1
  warn "--diff requires exactly one --case"
  exit 2
end

artifacts_root = File.expand_path(options[:artifacts] ||
  File.join(Dir.tmpdir, "comment-restatement-evals-#{Time.now.strftime("%Y%m%d-%H%M%S")}"))
FileUtils.mkdir_p(artifacts_root)

def prepare_checkout(root, directory)
  unless system("git", "clone", "--quiet", "--shared", root, directory)
    raise "git clone failed for #{root}"
  end
  unless system("git", "checkout", "--quiet", "master", chdir: directory)
    raise "git checkout master failed in #{directory}"
  end
  status, capture_status = Open3.capture2("git", "-C", directory, "status", "--porcelain")
  unless capture_status.success? && status.strip.empty?
    raise "checkout #{directory} is not clean: #{status}"
  end
  directory
end

def kill_process_tree(pid)
  Process.kill("TERM", -pid)
rescue Errno::ESRCH
  nil
end

def verify_process_tree_dead(pid)
  Process.kill(0, -pid)
  raise "process group #{pid} survived the kill"
rescue Errno::ESRCH
  nil
end

def run_agent(command_template, prompt_path:, out_path:, err_path:, cwd:, root: nil)
  argv = Shellwords.split(command_template).map { |token| token.gsub("{ROOT}", root || cwd) }
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid = spawn(*argv, in: prompt_path, out: out_path, err: err_path, chdir: cwd, pgroup: true)
  begin
    _child, status = Process.wait2(pid)
  rescue Interrupt
    kill_process_tree(pid)
    sleep 3
    begin
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      nil
    end
    verify_process_tree_dead(pid)
    raise
  end
  duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  [status, duration]
end

def capture_diff(checkout, path)
  system("git", "-C", checkout, "add", "-A") or raise "git add failed in #{checkout}"
  diff, status = Open3.capture2("git", "-C", checkout, "diff", "--cached")
  raise "git diff failed in #{checkout}" unless status.success?

  File.write(path, diff)
  diff
end

def parse_verdicts(stdout)
  text = stdout.strip
  start_index = text.index("{")
  raise "judge output contains no JSON object:\n#{text}" unless start_index

  end_index = text.rindex("}")
  raise "judge output contains no JSON object:\n#{text}" unless end_index

  parsed = JSON.parse(text[start_index..end_index])
  verdicts = parsed["verdicts"]
  raise "judge output has no verdicts array:\n#{text}" unless verdicts.is_a?(Array)

  verdicts
end

agent_command = options[:agent_command] || DEFAULT_AGENT_COMMAND
judge_command = options[:judge_command] || DEFAULT_JUDGE_COMMAND
schema_text = File.read(SCHEMA_PATH)
results = []

case_paths.each do |case_path|
  case_data = JSON.parse(File.read(case_path))
  task = case_data["task"]
  raise "case #{case_path} has no task" unless task.is_a?(String) && !task.empty?

  case_name = File.basename(case_path, ".json")
  case_dir = File.join(artifacts_root, case_name)
  FileUtils.mkdir_p(case_dir)

  rule_source = nil
  if options[:diff]
    diff = File.read(File.expand_path(options[:diff]))
    rule_source = root
    puts "== #{case_name}: judging the supplied diff with #{judge_command.split.first}"
  else
    checkout = prepare_checkout(root, File.join(case_dir, "checkout"))
    prompt_path = File.join(case_dir, "prompt.txt")
    File.write(prompt_path, "#{PROMPT_BASELINE}#{task}\n")

    puts "== #{case_name}: generating with #{agent_command.split.first}"
    _status, generation_seconds = run_agent(
      agent_command,
      prompt_path: prompt_path,
      out_path: File.join(case_dir, "generation-stdout.log"),
      err_path: File.join(case_dir, "generation-stderr.log"),
      cwd: case_dir,
      root: checkout,
    )
    diff = capture_diff(checkout, File.join(case_dir, "diff.patch"))
    rule_source = checkout
  end

  rule_path = File.join(rule_source, RULE_PATH_IN_CHECKOUT)
  raise "governing rule file missing from #{rule_source}: #{rule_path}" unless File.file?(rule_path)

  rule_text = File.read(rule_path)
  judge_prompt = JUDGE_INSTRUCTION
    .sub("<RULE>", rule_text)
    .sub("<DIFF>", diff)
    .sub("<SCHEMA>", schema_text)
  judge_prompt_path = File.join(case_dir, "judge-prompt.txt")
  File.write(judge_prompt_path, judge_prompt)

  puts "== #{case_name}: judging with #{judge_command.split.first}"
  _status, judge_seconds = run_agent(
    judge_command,
    prompt_path: judge_prompt_path,
    out_path: File.join(case_dir, "judge-stdout.log"),
    err_path: File.join(case_dir, "judge-stderr.log"),
    cwd: case_dir,
  )

  verdicts = parse_verdicts(File.read(File.join(case_dir, "judge-stdout.log")))
  passed = verdicts.empty?
  result = {
    "case" => case_name,
    "passed" => passed,
    "verdicts" => verdicts,
    "generation_seconds" => options[:diff] ? nil : generation_seconds&.round,
    "judge_seconds" => judge_seconds.round,
    "artifacts" => case_dir,
  }
  results << result
  File.write(File.join(case_dir, "report.json"), JSON.pretty_generate(result) + "\n")

  puts "== #{case_name}: #{passed ? "PASS" : "FAIL"} (#{verdicts.size} verdicts)"
  verdicts.each do |verdict|
    puts "   #{verdict["file"]}:#{verdict["line"]}: #{verdict["reason"]}"
  end
end

failures = results.count { |result| !result["passed"] }
puts "--"
puts format("%d case(s), %d failure(s)", results.size, failures)
exit(failures.zero? ? 0 : 1)
