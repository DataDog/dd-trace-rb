# frozen_string_literal: true

require 'find'
require 'open3'
require 'shellwords'

module DatadogLintTasks
  FROZEN_STRING_LITERAL_COMMENT = '# frozen_string_literal: true'
  MINIMUM_SUPPORTED_RUBY_VERSION = '4.0'
  RUBY_LINTER_MUTEX = Mutex.new

  GIT_CHANGED_FILE_COMMANDS = [
    %w[git diff --name-only --diff-filter=ACMR],
    %w[git diff --cached --name-only --diff-filter=ACMR],
    %w[git ls-files --others --exclude-standard]
  ].freeze

  RUBY_FILE_BASENAMES = %w[Gemfile Rakefile].freeze
  RUBY_FILE_EXTENSIONS = %w[.rb .rake .gemspec].freeze

  module_function

  def ensure_supported_lint_ruby!
    return unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new(MINIMUM_SUPPORTED_RUBY_VERSION)

    abort "Lint tasks are supported on Ruby #{MINIMUM_SUPPORTED_RUBY_VERSION} or newer"
  end

  def git_changed_files
    GIT_CHANGED_FILE_COMMANDS.flat_map { |command| capture_lines(command) }.uniq
  end

  def changed_files
    existing_files(git_changed_files)
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
    files_without_magic_comment = files_without_frozen_string_literal(files)

    if files_without_magic_comment.empty?
      puts "✅ #{success_message}"
    else
      puts "❌ The first line of the following .rb files should be '#{FROZEN_STRING_LITERAL_COMMENT}':"
      files_without_magic_comment.each { |file| puts "  - #{file}" }
      exit 1
    end
  end

  def capture_lines(command)
    output, status = Open3.capture2e(unbundled_environment, *command)

    if status.success?
      output.lines.map { |line| line.chomp }.reject { |line| line.empty? }
    else
      abort "Failed to list changed files with #{Shellwords.join(command)}:\n#{output}"
    end
  rescue Errno::ENOENT
    abort "Command failed to start: #{command.first}. Is it installed and on PATH?"
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

namespace :standard do
  desc 'Run standardrb on locally changed Ruby files'
  task fast: :"lint:supported_ruby" do
    ruby_files = DatadogLintTasks.changed_files.select { |path| DatadogLintTasks.ruby_file?(path) }

    if ruby_files.empty?
      puts 'standard:fast: no changed Ruby files'
      next
    end

    DatadogLintTasks::RUBY_LINTER_MUTEX.synchronize do
      require 'standard'

      exit_code = Standard::Cli.new(%w[--no-fix] + ruby_files).run
      fail unless exit_code == 0
    end
  end
end

namespace :rubocop do
  desc 'Run RuboCop on locally changed Ruby files'
  task fast: :"lint:supported_ruby" do
    ruby_files = DatadogLintTasks.changed_files.select { |path| DatadogLintTasks.ruby_file?(path) }

    if ruby_files.empty?
      puts 'rubocop:fast: no changed Ruby files'
      next
    end

    DatadogLintTasks::RUBY_LINTER_MUTEX.synchronize do
      require 'rubocop'

      exit_code = RuboCop::CLI.new.run(%w[--no-server --force-exclusion] + ruby_files)
      fail unless exit_code == 0
    end
  end
end

namespace :yamllint do
  desc 'Run yamllint on locally changed YAML files'
  task fast: :"lint:supported_ruby" do
    yaml_files = DatadogLintTasks.changed_files.select { |path| DatadogLintTasks.yaml_file?(path) }

    if yaml_files.empty?
      puts 'yamllint:fast: no changed YAML files'
      next
    end

    sh(*(%w[yamllint --strict] + yaml_files))
  end
end

namespace :actionlint do
  desc 'Run actionlint on locally changed GitHub workflow files'
  task fast: :"lint:supported_ruby" do
    workflow_files = DatadogLintTasks.changed_files.select { |path| DatadogLintTasks.workflow_file?(path) }

    if workflow_files.empty?
      puts 'actionlint:fast: no changed GitHub workflow files'
      next
    end

    sh(*(%w[actionlint -color] + workflow_files))
  end
end

namespace :lint do
  task :supported_ruby do
    DatadogLintTasks.ensure_supported_lint_ruby!
  end

  task all: [:frozen_string_literal]

  # standard-rb does not enable the Style/FrozenStringLiteralComment cop.
  # As we will still support Rubies < 3.4 for years, we need to check that all .rb files in lib folder start with frozen_string_literal: true.
  desc 'Check that all .rb files in lib folder start with frozen_string_literal: true'
  task frozen_string_literal: :supported_ruby do
    DatadogLintTasks.check_frozen_string_literal(
      DatadogLintTasks.lib_ruby_files,
      "All .rb files in lib folder have the '#{DatadogLintTasks::FROZEN_STRING_LITERAL_COMMENT}' magic comment"
    )
  end

  namespace :frozen_string_literal do
    desc 'Check frozen string literal comments on locally changed lib/**/*.rb files'
    task fast: :"lint:supported_ruby" do
      lib_ruby_files = DatadogLintTasks.changed_files.select { |path| DatadogLintTasks.lib_ruby_file?(path) }

      if lib_ruby_files.empty?
        puts 'lint:frozen_string_literal:fast: no changed lib/**/*.rb files'
        next
      end

      DatadogLintTasks.check_frozen_string_literal(
        lib_ruby_files,
        "Changed lib/**/*.rb files have the '#{DatadogLintTasks::FROZEN_STRING_LITERAL_COMMENT}' magic comment"
      )
    end
  end

  desc 'Run fast file-scoped lint checks for locally changed files'
  multitask fast: [
    :"standard:fast",
    :"rubocop:fast",
    :"lint:frozen_string_literal:fast",
    :"yamllint:fast",
    :"actionlint:fast"
  ]
end
