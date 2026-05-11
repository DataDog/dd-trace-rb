# frozen_string_literal: true

require 'find'
require 'open3'
require 'shellwords'

module DatadogLintTasks
  CheckResult = Struct.new(:command, :output, :success, :failure_message)

  FROZEN_STRING_LITERAL_COMMENT = '# frozen_string_literal: true'

  GIT_CHANGED_FILE_COMMANDS = [
    %w[git diff --name-only --diff-filter=ACMR],
    %w[git diff --cached --name-only --diff-filter=ACMR],
    %w[git ls-files --others --exclude-standard]
  ].freeze

  SKIPPED_CHANGED_FILE_CHECKS = [
    'rbs:stale',
    'rbs:missing',
    'full-repo steep:check',
    'single-file Steep',
    'semgrep ci',
    'zizmor'
  ].freeze

  RUBY_FILE_BASENAMES = %w[Gemfile Rakefile].freeze
  RUBY_FILE_EXTENSIONS = %w[.rb .rake .gemspec].freeze

  module_function

  def git_changed_files
    GIT_CHANGED_FILE_COMMANDS.flat_map { |command| capture_lines(command) }.uniq
  end

  def existing_files(paths)
    paths.select { |path| File.file?(path) }
  end

  def ruby_file?(path)
    RUBY_FILE_BASENAMES.include?(File.basename(path)) ||
      RUBY_FILE_EXTENSIONS.any? { |extension| path.end_with?(extension) }
  end

  def ruby_source_file?(path)
    path.end_with?('.rb')
  end

  def yaml_file?(path)
    path.end_with?('.yml', '.yaml')
  end

  def workflow_file?(path)
    File.dirname(path) == '.github/workflows' && yaml_file?(path)
  end

  def lib_ruby_file?(path)
    path.start_with?('lib/') && ruby_source_file?(path)
  end

  def lib_ruby_files
    files = []

    Find.find('lib') do |path|
      # Skip vendor folders
      Find.prune if File.basename(path) == 'vendor'

      next unless File.file?(path) && ruby_source_file?(path)

      files << path
    end

    files
  end

  def files_without_frozen_string_literal(files)
    files.each_with_object([]) do |path, files_without_magic_comment|
      # Skip binary files and symlinks
      next unless File.readable?(path) && !File.symlink?(path)

      begin
        first_line = File.open(path, 'r') { |f| f.gets&.strip }
        next if first_line == FROZEN_STRING_LITERAL_COMMENT

        files_without_magic_comment << path
      rescue => e
        puts "Warning: Could not read file #{path}: #{e.message}"
      end
    end
  end

  def check_frozen_string_literal(files, success_message)
    result = frozen_string_literal_result(files, success_message)

    print result.output
    unless result.success
      exit 1
    end
  end

  def set_fast_context(changed_files, missing_files, ruby_files, lib_ruby_files, yaml_files, workflow_files)
    @fast_context = {
      changed_files: changed_files,
      missing_files: missing_files,
      ruby_files: ruby_files,
      lib_ruby_files: lib_ruby_files,
      yaml_files: yaml_files,
      workflow_files: workflow_files,
      command_results: {},
      command_results_mutex: Mutex.new
    }
  end

  def fast_context
    @fast_context || raise('lint:fast context has not been initialized')
  end

  def record_command_result(name, command)
    record_result(name, capture_command(command))
  end

  def record_result(name, result)
    fast_context[:command_results_mutex].synchronize do
      fast_context[:command_results][name] = result
    end
  end

  def print_command_results
    command_results = fast_context[:command_results]
    results = [:standardrb, :rubocop, :frozen_string_literal, :yamllint, :actionlint].map { |name| command_results[name] }.compact
    failures = []
    failed = false

    results.each do |result|
      puts "$ #{Shellwords.join(result.command)}" if result.command
      print result.output unless result.output.empty?

      unless result.success
        failed = true
        failures << (result.failure_message || "Command failed: #{Shellwords.join(result.command)}") if result.command
      end
    end

    unless failures.empty?
      puts failures.join("\n")
    end

    if failed
      exit 1
    end
  end

  def frozen_string_literal_result(files, success_message)
    files_without_magic_comment = files_without_frozen_string_literal(files)

    if files_without_magic_comment.empty?
      CheckResult.new(nil, "✅ #{success_message}\n", true, nil)
    else
      output = +"❌ The first line of the following .rb files should be '#{FROZEN_STRING_LITERAL_COMMENT}':\n"
      files_without_magic_comment.each { |file| output << "  - #{file}\n" }
      CheckResult.new(nil, output, false, nil)
    end
  end

  def print_changed_file_summary(changed_files, missing_files, ruby_files, lib_ruby_files, yaml_files, workflow_files)
    puts 'lint:fast checks local staged, unstaged, and untracked files.'
    puts "Existing changed files: #{changed_files.length}"
    puts "Ignored missing/deleted files: #{missing_files.length}" unless missing_files.empty?
    puts 'Buckets:'
    puts "  Ruby (standardrb, rubocop): #{ruby_files.length}"
    puts "  lib/**/*.rb (frozen string literal): #{lib_ruby_files.length}"
    puts "  YAML (yamllint): #{yaml_files.length}"
    puts "  .github/workflows/*.yml|*.yaml (actionlint): #{workflow_files.length}"
    puts "Skipped project-level checks: #{SKIPPED_CHANGED_FILE_CHECKS.join(', ')}"
  end

  def capture_lines(command)
    result = capture_command(command)

    if result.failure_message
      abort result.failure_message
    elsif result.success
      result.output.lines.map { |line| line.chomp }.reject { |line| line.empty? }
    else
      abort "Failed to list changed files with #{Shellwords.join(command)}:\n#{result.output}"
    end
  end

  def capture_command(command)
    environment = command_environment(command)
    output, status =
      if environment
        Open3.capture2e(environment, *command)
      else
        Open3.capture2e(*command)
      end

    CheckResult.new(command, output, status.success?, nil)
  rescue Errno::ENOENT
    CheckResult.new(command, '', false, "Command failed to start: #{command.first}. Is it installed and on PATH?")
  end

  def command_environment(command)
    return if command.first == 'bundle'

    unbundled_environment
  end

  def unbundled_environment
    if defined?(Bundler) && Bundler.respond_to?(:unbundled_env)
      current_environment = ENV.to_hash
      environment = Bundler.unbundled_env

      current_environment.each_key do |key|
        environment[key] = nil unless environment.key?(key)
      end

      environment
    else
      {}
    end
  end
end

namespace :lint do
  task all: [:frozen_string_literal]

  # standard-rb does not enable the Style/FrozenStringLiteralComment cop.
  # As we will still support Rubies < 3.4 for years, we need to check that all .rb files in lib folder start with frozen_string_literal: true.
  desc 'Check that all .rb files in lib folder start with frozen_string_literal: true'
  task :frozen_string_literal do
    DatadogLintTasks.check_frozen_string_literal(
      DatadogLintTasks.lib_ruby_files,
      "All .rb files in lib folder have the '#{DatadogLintTasks::FROZEN_STRING_LITERAL_COMMENT}' magic comment"
    )
  end

  namespace :fast do
    task :detect do
      raw_changed_files = DatadogLintTasks.git_changed_files
      changed_files = DatadogLintTasks.existing_files(raw_changed_files)
      missing_files = raw_changed_files - changed_files

      ruby_files = changed_files.select { |path| DatadogLintTasks.ruby_file?(path) }
      lib_ruby_files = changed_files.select { |path| DatadogLintTasks.lib_ruby_file?(path) }
      yaml_files = changed_files.select { |path| DatadogLintTasks.yaml_file?(path) }
      workflow_files = changed_files.select { |path| DatadogLintTasks.workflow_file?(path) }

      DatadogLintTasks.set_fast_context(
        changed_files,
        missing_files,
        ruby_files,
        lib_ruby_files,
        yaml_files,
        workflow_files
      )

      DatadogLintTasks.print_changed_file_summary(
        changed_files,
        missing_files,
        ruby_files,
        lib_ruby_files,
        yaml_files,
        workflow_files
      )
    end

    task :standardrb do
      ruby_files = DatadogLintTasks.fast_context[:ruby_files]
      next if ruby_files.empty?

      DatadogLintTasks.record_command_result(:standardrb, %w[bundle exec standardrb --no-fix] + ruby_files)
    end

    task :rubocop do
      ruby_files = DatadogLintTasks.fast_context[:ruby_files]
      next if ruby_files.empty?

      DatadogLintTasks.record_command_result(:rubocop, %w[bundle exec rubocop --no-server --force-exclusion] + ruby_files)
    end

    task :yamllint do
      yaml_files = DatadogLintTasks.fast_context[:yaml_files]
      next if yaml_files.empty?

      DatadogLintTasks.record_command_result(:yamllint, %w[yamllint --strict] + yaml_files)
    end

    task :actionlint do
      workflow_files = DatadogLintTasks.fast_context[:workflow_files]
      next if workflow_files.empty?

      DatadogLintTasks.record_command_result(:actionlint, %w[actionlint -color] + workflow_files)
    end

    task :frozen_string_literal do
      lib_ruby_files = DatadogLintTasks.fast_context[:lib_ruby_files]
      next if lib_ruby_files.empty?

      DatadogLintTasks.record_result(
        :frozen_string_literal,
        DatadogLintTasks.frozen_string_literal_result(
          lib_ruby_files,
          "Changed lib/**/*.rb files have the '#{DatadogLintTasks::FROZEN_STRING_LITERAL_COMMENT}' magic comment"
        )
      )
    end

    multitask tools: [:standardrb, :rubocop, :frozen_string_literal, :yamllint, :actionlint]
  end

  desc 'Run fast file-scoped lint checks for locally changed files'
  task fast: [:"fast:detect", :"fast:tools"] do
    context = DatadogLintTasks.fast_context

    if context[:ruby_files].empty? && context[:yaml_files].empty? && context[:workflow_files].empty?
      puts 'lint:fast: nothing to check'
    else
      DatadogLintTasks.print_command_results
    end
  end
end
