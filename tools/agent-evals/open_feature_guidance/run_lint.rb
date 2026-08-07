# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'tmpdir'

DEFAULT_ROOT = File.expand_path('../../..', __dir__)
FIXTURES_DIR = File.join(__dir__, 'fixtures')
LINT_CASES_DIR = File.join(__dir__, 'lint_cases')
RUBOCOP_COMMAND = /(?:^|[';&|]\s*)(?:[A-Z_][A-Z0-9_]*=\S+\s+)*(?:(?:bundle|rbenv)\s+exec\s+)?rubocop(?:\s|$)/

options = {cases: [], model: nil, root: DEFAULT_ROOT, revision: 'HEAD'}
OptionParser.new do |parser|
  parser.banner = 'Usage: ruby tools/agent-evals/open_feature_guidance/run_lint.rb [options]'
  parser.on('--case NAME', 'Run one named case (repeatable)') { |name| options[:cases] << name }
  parser.on('--model MODEL', 'Pass a model override to codex exec') { |model| options[:model] = model }
  parser.on('--root PATH', 'Evaluate another repository checkout') { |root| options[:root] = root }
  parser.on('--revision REV', 'Evaluate a revision from the selected checkout') { |rev| options[:revision] = rev }
end.parse!

evaluation_root = File.expand_path(options[:root])
unless File.directory?(evaluation_root)
  warn "Unknown evaluation root: #{evaluation_root}"
  exit 2
end

case_paths =
  if options[:cases].empty?
    Dir[File.join(LINT_CASES_DIR, '*.json')].sort
  else
    options[:cases].map { |name| File.join(LINT_CASES_DIR, "#{name}.json") }
  end

missing_case_paths = case_paths.reject { |path| File.file?(path) }
unless missing_case_paths.empty?
  names = missing_case_paths.map { |path| File.basename(path, '.json') }
  warn "Unknown lint eval case(s): #{names.join(', ')}"
  exit 2
end

def capture(*command, chdir:, env: {})
  Open3.capture3(env, *command, chdir: chdir)
end

def run!(*command, chdir:, env: {})
  stdout, stderr, status = capture(*command, chdir: chdir, env: env)
  return stdout if status.success?

  raise "#{command.join(' ')} failed (#{status.exitstatus})\n#{stderr}\n#{stdout}"
end

def create_worktree(root, workspace, revision)
  run!('git', 'worktree', 'add', '--detach', workspace, revision, chdir: root)
end

def remove_worktree(root, workspace)
  _stdout, stderr, status = capture('git', 'worktree', 'remove', '--force', workspace, chdir: root)
  warn "Could not remove eval worktree #{workspace}: #{stderr}" unless status.success?
end

def install_fixtures(case_config, workspace)
  target_file = case_config.fetch('target_file')
  target_path = File.join(workspace, target_file)
  gemfile = File.join(workspace, '.agent-eval.gemfile')
  FileUtils.mkdir_p(File.dirname(target_path))
  FileUtils.cp(File.join(FIXTURES_DIR, case_config.fetch('target_fixture')), target_path)
  FileUtils.cp(File.join(FIXTURES_DIR, case_config.fetch('rubocop_fixture')), File.join(workspace, '.rubocop.yml'))
  FileUtils.cp(File.join(FIXTURES_DIR, case_config.fetch('gemfile_fixture')), gemfile)

  bundle_env = {'BUNDLE_GEMFILE' => gemfile}
  run!('bundle', 'lock', '--local', chdir: workspace, env: bundle_env)

  run!('git', 'add', '.agent-eval.gemfile', '.rubocop.yml', target_file, chdir: workspace)
  run!(
    'git',
    '-c', 'user.name=OpenFeature agent eval',
    '-c', 'user.email=openfeature-agent-eval@example.invalid',
    'commit', '--no-gpg-sign', '-m', 'Add lint eval fixture',
    chdir: workspace
  )

  bundle_env
end

def run_codex(prompt, model, workspace, env)
  command = [
    'codex', 'exec',
    '--ephemeral',
    '--ignore-user-config',
    '--sandbox', 'workspace-write',
    '--color', 'never',
    '--cd', workspace,
    '--json'
  ]
  command.concat(['--model', model]) if model
  command << prompt

  capture(*command, chdir: workspace, env: env)
end

def command_results_from_trace(trace)
  trace.each_line.each_with_object([]) do |line, results|
    event = JSON.parse(line)
    item = event['item']
    next unless event['type'] == 'item.completed'
    next unless item && item['type'] == 'command_execution'

    results << {command: item.fetch('command'), exit_code: item['exit_code']}
  rescue JSON::ParserError
    next
  end
end

def changed_paths(workspace)
  modified = run!('git', 'diff', '--name-only', 'HEAD', chdir: workspace).lines.map(&:strip)
  untracked = run!('git', 'ls-files', '--others', '--exclude-standard', chdir: workspace).lines.map(&:strip)
  (modified + untracked).reject(&:empty?).uniq
end

def rubocop_result(target_file, workspace, env)
  capture('bundle', 'exec', 'rubocop', '--config', '.rubocop.yml', target_file, chdir: workspace, env: env)
end

failures = []

case_paths.each do |case_path|
  case_config = JSON.parse(File.read(case_path))
  name = case_config.fetch('name')

  Dir.mktmpdir("open-feature-lint-eval-#{name}") do |tmpdir|
    workspace = File.join(tmpdir, 'repo')
    worktree_created = false

    begin
      create_worktree(evaluation_root, workspace, options[:revision])
      worktree_created = true
      bundle_env = install_fixtures(case_config, workspace)

      trace, codex_stderr, codex_status = run_codex(case_config.fetch('prompt'), options[:model], workspace, bundle_env)
      command_results = command_results_from_trace(trace)
      rubocop_results = command_results.select { |result| result.fetch(:command).match?(RUBOCOP_COMMAND) }
      rubocop_evidence = rubocop_results.map do |result|
        "#{result.fetch(:command)} (exit #{result.fetch(:exit_code).inspect})"
      end
      target_file = case_config.fetch('target_file')
      lint_stdout, lint_stderr, lint_status = rubocop_result(target_file, workspace, bundle_env)
      unexpected_paths = changed_paths(workspace) - [target_file]
      target_contents = File.read(File.join(workspace, target_file))

      errors = []
      errors << "codex exec failed (#{codex_status.exitstatus})\n#{codex_stderr}" unless codex_status.success?
      errors << 'no RuboCop command observed in Codex trace' if rubocop_results.empty?
      errors << "RuboCop post-check failed\n#{lint_stderr}\n#{lint_stdout}" unless lint_status.success?
      errors << "target does not contain #{case_config.fetch('expected_text').inspect}" unless target_contents.include?(case_config.fetch('expected_text'))
      errors << "unexpected changed paths: #{unexpected_paths.join(', ')}" unless unexpected_paths.empty?
      errors << "observed RuboCop command(s): #{rubocop_evidence.join(' | ')}" unless rubocop_evidence.empty? || errors.empty?

      if errors.empty?
        puts "PASS #{name}"
        puts "  observed: #{rubocop_evidence.join(' | ')}"
        puts '  post-check: RuboCop clean; requested change present; only target file changed'
      else
        failures << [name, errors.join("\n")]
      end
    rescue JSON::ParserError, KeyError, RuntimeError => e
      failures << [name, e.message]
    ensure
      remove_worktree(evaluation_root, workspace) if worktree_created
    end
  end
end

unless failures.empty?
  failures.each do |name, details|
    warn "FAIL #{name}"
    warn details
  end
  exit 1
end

puts "#{case_paths.length} lint eval(s) passed"
