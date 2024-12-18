require 'pathname'
require 'rubygems'
require 'json'
require 'bundler'

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'datadog'

def parse_gemfiles(directory = 'gemfiles/')
  minimum_gems_ruby = {}
  minimum_gems_jruby = {}
  maximum_gems_ruby = {}
  maximum_gems_jruby = {}


  gemfiles = Dir.glob(File.join(directory, '*'))
  gemfiles.each do |gemfile_name|
    runtime = File.basename(gemfile_name).split('_').first # ruby or jruby
    # parse the gemfile
    if gemfile_name.end_with?(".gemfile")
      begin
        definition = Bundler::Definition.build(gemfile_name, nil, nil)
    
        definition.dependencies.each do |dependency|
          gem_name, version = dependency.name, dependency.requirement
          # puts "Gem: #{dependency.name}, Version: #{dependency.requirement}"
          if version_valid?(version)
            case runtime
            when 'ruby'
              update_min_max(minimum_gems_ruby, maximum_gems_ruby, gem_name, version)
            when 'jruby'
              update_min_max(minimum_gems_jruby, maximum_gems_jruby, gem_name, version)
            end
          else
            next
          end
      end
      rescue Bundler::GemfileError => e
        puts "Error reading Gemfile: #{e.message}"
      end
    elsif gemfile_name.end_with?(".gemfile.lock")
      lockfile_contents = File.read(gemfile_name)
      parser = Bundler::LockfileParser.new(lockfile_contents)
      parser.specs.each do |spec|
        # puts "Gem: #{spec.name}, Version: #{spec.version}"
        gem_name, version = spec.name, spec.version.to_s
        if version_valid?(version)
          case runtime
          when 'ruby'
            update_min_max(minimum_gems_ruby, maximum_gems_ruby, gem_name, version)
          when 'jruby'
            update_min_max(minimum_gems_jruby, maximum_gems_jruby, gem_name, version)
          end
        else
          next
        end
      end
    end
  end

  [minimum_gems_ruby, minimum_gems_jruby, maximum_gems_ruby, maximum_gems_jruby]
end


def update_min_max(minimum_gems, maximum_gems, gem_name, version)
  gem_version = Gem::Version.new(version)
  
  if minimum_gems[gem_name].nil? || gem_version < Gem::Version.new(minimum_gems[gem_name])
    minimum_gems[gem_name] = version
  end
  
  if maximum_gems[gem_name].nil? || gem_version > Gem::Version.new(maximum_gems[gem_name])
    maximum_gems[gem_name] = version
  end
end

def parse_gemfile(gemfile_path)
  # Helper: Parse a Gemfile
  begin
    definition = Bundler::Definition.build(gemfile_path, nil, nil)

    definition.dependencies.each do |dependency|
      puts "Gem: #{dependency.name}, Version: #{dependency.requirement}"
    end
  end
  rescue Bundler::GemfileError => e
    puts "Error reading Gemfile: #{e.message}"
  end


# Helper: Validate the version format
def version_valid?(version)
  return false if version.nil?

  # Convert to string if version is not already a string
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


# Helper: Extract the actual version number from a constraint
# Matches on the following version patterns:
# 1. "pessimistic" versions, ex. '~> 1.2.3'
# 2. '>= 1.2.3'
# 3. 1.2.3
def extract_version(constraint)
  if constraint =~ /~>\s*([\d.]+(?:[-.\w]*))| # Handles ~> constraints
                     >=\s*([\d.]+(?:[-.\w]*))| # Handles >= constraints
                     ([\d.]+(?:[-.\w]*))       # Handles plain versions
                    /x
    Regexp.last_match(1) || Regexp.last_match(2) || Regexp.last_match(3)
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
