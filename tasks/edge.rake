require 'bundler'
require 'open3'

require_relative 'appraisal_conversion'
require_relative 'runtime_matcher'

CHANGE_TYPES = [
  {key: 'major', emoji: '🛑', label: 'Major'},
  {key: 'promotion', emoji: '🚀', label: 'Promotion'},
  {key: 'downgrade', emoji: '🔙', label: 'Downgrade'},
  {key: 'unknown', emoji: '❔', label: 'Unknown'},
  {key: 'prerelease', emoji: '🧪', label: 'Prerelease'},
  {key: 'minor', emoji: '⚠️', label: 'Minor'},
  {key: 'patch', emoji: '🟢', label: 'Patch'},
].freeze
CHANGE_TYPE_ORDER = CHANGE_TYPES.map { |type| type[:key] }.freeze
CHANGE_TYPE_PRIORITY = CHANGE_TYPE_ORDER.each_with_index.to_h.freeze
DEFAULT_CHANGE_EMOJI = CHANGE_TYPES.find { |type| type[:key] == 'unknown' }[:emoji]
CHANGE_TYPE_EMOJI = CHANGE_TYPES.each_with_object(Hash.new(DEFAULT_CHANGE_EMOJI)) do |type, hash|
  hash[type[:key]] = type[:emoji]
end.freeze
CHANGE_TYPE_LABEL = CHANGE_TYPES.to_h { |type| [type[:key], type[:label]] }.freeze

# rubocop:disable Metrics/BlockLength
namespace :edge do
  desc 'Update all the groups with gemspec dependencies'
  task :gemspec do |_t, _args|
    candidates = Set.new

    TEST_METADATA.each do |_, metadata|
      metadata.each do |group, rubies|
        candidates << group if RuntimeMatcher.match?(rubies)
      end
    end

    gemspec_runtime_dependencies = Gem::Specification.load('datadog.gemspec').dependencies

    candidates.each do |group|
      next if group.empty?

      gemfile = AppraisalConversion.to_bundle_gemfile(group)

      Bundler.with_unbundled_env do
        output, = Open3.capture2e(
          {'BUNDLE_GEMFILE' => gemfile.to_s},
          "bundle lock --update=#{gemspec_runtime_dependencies.map(&:name).join(" ")}"
        )

        puts output
      end
    end
  end

  desc 'Update groups with targeted dependencies'
  task :update do |_t, args|
    # Naming convention:
    #
    # Key: integration name, the same as the name of spec task in Rakefile and MatrixFile
    # Value: gem name
    allowlist = {
      'stripe' => 'stripe',
      'elasticsearch' => 'elasticsearch',
      'opensearch' => 'opensearch-ruby',
      'rack' => 'rack',
      'faraday' => 'faraday',
      'excon' => 'excon',
      'rest_client' => 'rest-client',
      'mongodb' => 'mongo',
      'dalli' => 'dalli',
      'redis' => 'redis',
      'karafka' => 'karafka',
      # Add more integrations here, when they are extracted to its own isolated group
    }

    allowlist = allowlist.slice(*args.extras) if args.extras.any?

    allowlist.each do |integration, gem|
      candidates = TEST_METADATA.fetch(integration).select do |_, rubies|
        RuntimeMatcher.match?(rubies)
      end

      candidates.each do |group, _|
        gemfile = AppraisalConversion.to_bundle_gemfile(group)

        Bundler.with_unbundled_env do
          output, = Open3.capture2e({'BUNDLE_GEMFILE' => gemfile.to_s}, "bundle lock --update=#{gem}")

          puts output
        end
      end
    end
  end

  desc 'Generate a markdown changes summary for gem updates (default: working tree against HEAD)'
  task :changes_summary, [:before_ref, :after_ref] do |_t, args|
    before_ref = args[:before_ref]
    after_ref = args[:after_ref]

    if before_ref || after_ref
      after_ref ||= 'HEAD'
      before_ref ||= "#{after_ref}^"
    else
      before_ref = 'HEAD'
    end

    rows = build_update_rows(before_ref, after_ref)
    sorted_rows = sort_update_rows(rows)
    render_changes_summary(sorted_rows)
  end

  def git_capture(*args)
    output, status = Open3.capture2e('git', '-c', 'core.fsmonitor=false', *args)
    raise "git #{args.join(" ")} failed\n#{output}" unless status.success?

    output
  end

  def build_update_rows(before_ref, after_ref)
    changed_files = changed_lockfiles(before_ref, after_ref)
    aggregated = aggregated_updates

    changed_files.each do |file|
      collect_file_updates(aggregated, before_ref, after_ref, file)
    end

    aggregated.values
  end

  def sort_update_rows(rows)
    rows.sort_by do |row|
      [
        CHANGE_TYPE_PRIORITY[row[:type]],
        -row[:files].length,
        row[:gem],
        row[:from],
        row[:to]
      ]
    end
  end

  def render_changes_summary(rows)
    puts '| Gem | Type | Version | Files |'
    puts '|---|---|---|---|'
    rows.each { |row| puts row_to_markdown(row) }
  end

  def row_to_markdown(row)
    gem = "[#{row[:gem]}](https://rubygems.org/gems/#{row[:gem]})"
    type = "#{CHANGE_TYPE_EMOJI[row[:type]]} #{CHANGE_TYPE_LABEL[row[:type]]}"
    version = inline_version_diff(row[:from], row[:to])
    "| #{gem} | #{type} | #{version} | #{files_cell(row[:files])} |"
  end

  def files_cell(files)
    sorted_files = files.to_a.sort
    files_body = sorted_files.join('<br>')
    "<details><summary>show (#{sorted_files.length})</summary>#{files_body}</details>"
  end

  def aggregated_updates
    Hash.new do |hash, key|
      hash[key] = {
        gem: key[0],
        from: key[1],
        to: key[2],
        type: key[3],
        files: Set.new
      }
    end
  end

  def collect_file_updates(aggregated, before_ref, after_ref, file)
    old_lock = lockfile_content(before_ref, file)
    new_lock = lockfile_content(after_ref, file)
    return if old_lock.nil? || new_lock.nil?

    old_specs = parse_lockfile_specs(old_lock)
    new_specs = parse_lockfile_specs(new_lock)
    shared_keys = old_specs.keys & new_specs.keys

    shared_keys.each do |spec_key|
      from_version = old_specs[spec_key]
      to_version = new_specs[spec_key]
      next if from_version == to_version

      gem_name = spec_key[0]
      type = classify_change(from_version, to_version)
      row_key = [gem_name, from_version.to_s, to_version.to_s, type]
      aggregated[row_key][:files] << file
    end
  end

  def changed_lockfiles(before_ref, after_ref)
    refs = [before_ref, after_ref].compact
    diff_output = git_capture('diff', '--name-only', *refs, '--', 'gemfiles')

    diff_output
      .lines
      .map(&:strip)
      .reject(&:empty?)
      .grep(/\.gemfile\.lock\z/)
  end

  def lockfile_content(ref, file)
    return File.read(file) if ref.nil?

    git_show_file(ref, file)
  rescue Errno::ENOENT
    nil
  end

  def git_show_file(ref, file)
    output, status = Open3.capture2e('git', '-c', 'core.fsmonitor=false', 'show', "#{ref}:#{file}")
    return output if status.success?

    nil
  end

  def parse_lockfile_specs(content)
    parser = Bundler::LockfileParser.new(content)
    parser.specs.each_with_object({}) do |spec, specs|
      specs[[spec.name, spec.platform.to_s]] = Gem::Version.new(spec.version.to_s)
    end
  end

  def first_changed_release_segment(from_version, to_version)
    from_segments = from_version.release.segments
    to_segments = to_version.release.segments
    max_length = [from_segments.length, to_segments.length].max

    (0...max_length).each do |index|
      left = from_segments[index] || 0
      right = to_segments[index] || 0
      return index if left != right
    end

    nil
  end

  def classify_change(from_version, to_version)
    return 'unknown' if from_version == to_version
    return 'downgrade' if to_version < from_version
    if from_version.prerelease? && !to_version.prerelease? && to_version > from_version
      return 'promotion'
    end
    return 'prerelease' if from_version.prerelease? || to_version.prerelease?

    segment = first_changed_release_segment(from_version, to_version)
    return 'major' if segment == 0
    return 'minor' if segment == 1
    return 'patch' if segment && segment >= 2

    'unknown'
  rescue ArgumentError, NoMethodError
    'unknown'
  end

  def inline_version_diff(from_version, to_version)
    from = from_version.to_s
    to = to_version.to_s

    from_parts = from.split('.')
    to_parts = to.split('.')

    prefix_size = 0
    max_prefix = [from_parts.length, to_parts.length].min
    while prefix_size < max_prefix && from_parts[prefix_size] == to_parts[prefix_size]
      prefix_size += 1
    end

    suffix_size = 0
    max_suffix = [from_parts.length - prefix_size, to_parts.length - prefix_size].min
    while suffix_size < max_suffix && from_parts[-(suffix_size + 1)] == to_parts[-(suffix_size + 1)]
      suffix_size += 1
    end

    prefix_parts = from_parts[0, prefix_size]
    suffix_parts = suffix_size.zero? ? [] : from_parts[-suffix_size, suffix_size]

    from_middle_parts = from_parts[prefix_size, from_parts.length - prefix_size - suffix_size]
    to_middle_parts = to_parts[prefix_size, to_parts.length - prefix_size - suffix_size]

    prefix = prefix_parts.empty? ? '' : "#{prefix_parts.join(".")}."
    suffix = suffix_parts.empty? ? '' : ".#{suffix_parts.join(".")}"
    changed = "<strong>{#{from_middle_parts.join(".")}→#{to_middle_parts.join(".")}}</strong>"

    "#{prefix}#{changed}#{suffix}"
  end
end
# rubocop:enable Metrics/BlockLength
