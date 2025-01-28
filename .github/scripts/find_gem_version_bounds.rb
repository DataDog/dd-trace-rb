require 'pathname'
require 'rubygems'
require 'json'
require 'bundler'

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'datadog'

class GemfileProcessor
  SPECIAL_CASES = {
    "opensearch" => "OpenSearch", # special case because opensearch = OpenSearch not Opensearch
  }.freeze
  EXCLUDED_INTEGRATIONS = ["configuration", "propagation", "utils"].freeze

  def initialize(directory: 'gemfiles/', contrib_dir: 'lib/datadog/tracing/contrib/')
    @directory = directory
    @contrib_dir = contrib_dir
    @min_gems = { 'ruby' => {}, 'jruby' => {} }
    @max_gems = { 'ruby' => {}, 'jruby' => {} }
    @integration_json_mapping = {}
  end

  def process
    parse_gemfiles
    process_integrations
    include_hardcoded_versions
    write_markdown_output
  end

  private


  def parse_gemfiles(directory = 'gemfiles/')
    gemfiles = Dir.glob(File.join(@directory, '*'))
    gemfiles.each do |gemfile_name|
      runtime = File.basename(gemfile_name).split('_').first # ruby or jruby
      next unless %w[ruby jruby].include?(runtime)
      # parse the gemfile
      if gemfile_name.end_with?('.gemfile.lock')
        process_lockfile(gemfile_name, runtime)
      end
    end

  end

  def process_lockfile(gemfile_name, runtime)
    lockfile_contents = File.read(gemfile_name)
    parser = Bundler::LockfileParser.new(lockfile_contents)
    parser.specs.each do |spec|
      gem_name = spec.name
      version = spec.version.to_s
      update_gem_versions(runtime, gem_name, version, false)
    end
  end

  def update_gem_versions(runtime, gem_name, version, unspecified)
    return unless version_valid?(version, unspecified)

    gem_version = Gem::Version.new(version) unless unspecified
    # Update minimum gems
    if not unspecified
      if @min_gems[runtime][gem_name].nil? || gem_version < Gem::Version.new(@min_gems[runtime][gem_name])
        @min_gems[runtime][gem_name] = version
      end
    end

    # Update maximum gems
    if unspecified
      @max_gems[runtime][gem_name] = Float::INFINITY
    else
      if @max_gems[runtime][gem_name].nil? || (@max_gems[runtime][gem_name] != Float::INFINITY && gem_version > Gem::Version.new(@max_gems[runtime][gem_name]))
        @max_gems[runtime][gem_name] = version
      end
    end
  end

  # Helper: Validate the version format
  def version_valid?(version, unspecified)
    return true if unspecified
    return false if version.nil? || version.strip.empty?
    Gem::Version.new(version)
    true
  rescue ArgumentError
    puts "#{version} is invalid format."
    false
  end


  def process_integrations
    integrations = Datadog::Tracing::Contrib::REGISTRY.map(&:name).map(&:to_s)
    integrations.each do |integration|
      next if EXCLUDED_INTEGRATIONS.include?(integration)

      integration_name = resolve_integration_name(integration)

      @integration_json_mapping[integration] = [
        @min_gems['ruby'][integration_name],
        @max_gems['ruby'][integration_name],
        @min_gems['jruby'][integration_name],
        @max_gems['jruby'][integration_name]
      ]
    end
  end

  def include_hardcoded_versions
      # `httpx` is maintained externally
    @integration_json_mapping['httpx'] = [
      '0.11',         # Min version Ruby
      'infinity',     # Max version Ruby
      '0.11',         # Min version JRuby
      'infinity'      # Max version JRuby
    ]

    # `makara` is part of `activerecord`
    @integration_json_mapping['makara'] = [
      '0.3.5',        # Min version Ruby
      'infinity',     # Max version Ruby
      '0.3.5',        # Min version JRuby
      'infinity'      # Max version JRuby
    ]
  end

  def resolve_integration_name(integration)
    mod_name = SPECIAL_CASES[integration] || integration.split('_').map(&:capitalize).join
    module_name = "Datadog::Tracing::Contrib::#{mod_name}"
    integration_module = Object.const_get(module_name)::Integration
    integration_module.respond_to?(:gem_name) ? integration_module.gem_name : integration
  rescue NameError, NoMethodError
    puts "Fallback for #{integration}: module or gem_name not found."
    integration
  end

  def write_markdown_output
    output_file = 'docs/integration_versions.md'
    comment = <<~COMMENT
      <!--
      ### Supported Versions Table ###
  
      This markdown file is generated from the minimum and maximum versions of the integrations we support, as tested in our `gemfile.lock` lockfiles.
      -->
    COMMENT
    header = "| Integration              | Ruby Min | Ruby Max | JRuby Min | JRuby Max |\n"
    separator = "|--------------------------|----------|----------|-----------|-----------|\n"
    column_widths = {
      integration: 24,
      ruby_min: 8,
      ruby_max: 8,
      jruby_min: 9,
      jruby_max: 9
    }
    rows = @integration_json_mapping.map do |name, versions|
      integration_name = name.ljust(column_widths[:integration])
      ruby_min = (versions[0] || "None").ljust(column_widths[:ruby_min])
      ruby_max = (versions[1] || "None").ljust(column_widths[:ruby_max])
      jruby_min = (versions[2] || "None").ljust(column_widths[:jruby_min])
      jruby_max = (versions[3] || "None").ljust(column_widths[:jruby_max])
  
      "| #{integration_name} | #{ruby_min} | #{ruby_max} | #{jruby_min} | #{jruby_max} |"
    end
  
    File.open(output_file, 'w') do |file|
      file.puts comment
      file.puts header
      file.puts separator
      rows.each { |row| file.puts row }
    end
  end
end


GemfileProcessor.new.process