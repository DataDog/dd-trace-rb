require 'pathname'
require 'rubygems'
require 'json'
require 'bundler'

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'datadog'

def parse_gemfiles(directory = 'gemfiles/')
  min_gems = { 'ruby' => {}, 'jruby' => {} }
  max_gems = { 'ruby' => {}, 'jruby' => {} }

  gemfiles = Dir.glob(File.join(directory, '*'))
  gemfiles.each do |gemfile_name|
    runtime = File.basename(gemfile_name).split('_').first # ruby or jruby
    next unless %w[ruby jruby].include?(runtime)
    # parse the gemfile
    if gemfile_name.end_with?(".gemfile")
      process_gemfile(gemfile_name, runtime, min_gems, max_gems)
    elsif gemfile_name.end_with?('.gemfile.lock')
      process_lockfile(gemfile_name, runtime, min_gems, max_gems)
    end
  end

  [min_gems['ruby'], min_gems['jruby'], max_gems['ruby'], max_gems['jruby']]
end

def process_gemfile(gemfile_name, runtime, min_gems, max_gems)
  begin
    definition = Bundler::Definition.build(gemfile_name, nil, nil)
    definition.dependencies.each do |dependency|
      gem_name = dependency.name
      version = dependency.requirement.to_s
      update_gem_versions(runtime, gem_name, version, min_gems, max_gems)
    end
  rescue Bundler::GemfileError => e
    puts "Error reading Gemfile: #{e.message}"
  end
end

def process_lockfile(gemfile_name, runtime, min_gems, max_gems)
  lockfile_contents = File.read(gemfile_name)
  parser = Bundler::LockfileParser.new(lockfile_contents)
  parser.specs.each do |spec|
    gem_name = spec.name
    version = spec.version.to_s
    update_gem_versions(runtime, gem_name, version, min_gems, max_gems)
  end
end

def update_gem_versions(runtime, gem_name, version, min_gems, max_gems)
  return unless version_valid?(version)

  gem_version = Gem::Version.new(version)

  # Update minimum gems
  if min_gems[runtime][gem_name].nil? || gem_version < Gem::Version.new(min_gems[runtime][gem_name])
    min_gems[runtime][gem_name] = version
  end

  # Update maximum gems
  if max_gems[runtime][gem_name].nil? || gem_version > Gem::Version.new(max_gems[runtime][gem_name])
    max_gems[runtime][gem_name] = version
  end
end



# Helper: Validate the version format
def version_valid?(version)
  return false if version.nil?

  version = version.to_s.strip

  return false if version.empty?

  # Ensure it's a valid Gem::Version
  begin
    Gem::Version.new(version)
    true
  rescue ArgumentError
    false
  end
end

def get_integration_names(directory = 'lib/datadog/tracing/contrib/')
  Datadog::Tracing::Contrib::REGISTRY.map{ |i| i.name.to_s }
end

# TODO: The gem information should reside in the integration declaration instead of here.

mapping = {
  "action_mailer" => "actionmailer",
  "opensearch" => "opensearch-ruby",
  "concurrent_ruby" => "concurrent-ruby",
  "action_view" => "actionview",
  "action_cable" => "actioncable",
  "active_record" => "activerecord",
  "mongodb" => "mongo",
  "rest_client" => "rest-client",
  "active_support" => "activesupport",
  "action_pack" => "actionpack",
  "active_job" => "activejob",
  "httprb" => "http",
  "kafka" => "ruby-kafka",
  "presto" => "presto-client",
  "aws" => "aws-sdk-core"
}

excluded = ["configuration", "propagation", "utils"]
min_gems_ruby, min_gems_jruby, max_gems_ruby, max_gems_jruby = parse_gemfiles("gemfiles/")
integrations = get_integration_names('lib/datadog/tracing/contrib/')

integration_json_mapping = {}

integrations.each do |integration|
  if excluded.include?(integration)
    next
  end
  integration_name = mapping[integration] || integration

  min_version_jruby = min_gems_jruby[integration_name]
  min_version_ruby = min_gems_ruby[integration_name]
  max_version_jruby = max_gems_jruby[integration_name]
  max_version_ruby = max_gems_ruby[integration_name]

  # mapping jruby, ruby
  integration_json_mapping[integration] = [min_version_ruby, max_version_ruby, min_version_jruby, max_version_jruby]
  integration_json_mapping.replace(integration_json_mapping.sort.to_h)
end

File.write("gem_output.json", JSON.pretty_generate(integration_json_mapping))
