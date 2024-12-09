require 'pathname'
require 'rubygems'
require 'json'

def parse_gemfiles(directory = 'gemfiles/')
  parsed_gems_ruby = {}
  parsed_gems_jruby = {}

  gemfiles = Dir.glob(File.join(directory, '*'))
  gemfiles.each do |gemfile_name|
    runtime = File.basename(gemfile_name).split('_').first # ruby or jruby
    # puts "Runtime: #{runtime}"
    File.foreach(gemfile_name) do |line|
      if (gem_details = parse_gemfile_entry(line))
        gem_name, version = gem_details
      elsif (gem_details = parse_gemfile_lock_entry(line))
        gem_name, version = gem_details
      else
        next
      end

      # Validate and store the minimum version
      if version_valid?(version)
        if runtime == 'ruby'
          if parsed_gems_ruby[gem_name].nil? || Gem::Version.new(version) < Gem::Version.new(parsed_gems_ruby[gem_name])
            parsed_gems_ruby[gem_name] = version
          end
        end
        if runtime == 'jruby'
          if parsed_gems_jruby[gem_name].nil? || Gem::Version.new(version) < Gem::Version.new(parsed_gems_jruby[gem_name])
            parsed_gems_jruby[gem_name] = version
          end
        end
      else
        next
      end
    end
  end

  [parsed_gems_ruby, parsed_gems_jruby]
end

# Helper: Parse a Gemfile-style gem declaration
# ex. gem 'ruby-kafka', '~> 5.0'
def parse_gemfile_entry(line)
  if (match = line.match(/^\s*gem\s+["']([^"']+)["']\s*,?\s*["']?([^"']*)["']?/))
    gem_name, version_constraint = match[1], match[2]
    version = extract_version(version_constraint)
    [gem_name, version]
  end
end

# Helper: Parse a Gemfile.lock-style entry
# matches on ex. actionmailer (= 6.0.6)
def parse_gemfile_lock_entry(line)
  if (match = line.match(/^\s*([a-z0-9_-]+)\s+\(([^)]+)\)/))
    [match[1], match[2]]
  end
end

# Helper: Validate the version format
def version_valid?(version)
  version =~ /^\d+(\.\d+)*$/
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
  unless Dir.exist?(directory)
    puts "Directory '#{directory}' not found!"
    return []
  end

  # Get all subdirectories inside the specified directory
  Dir.children(directory).select do |entry|
    File.directory?(File.join(directory, entry))
  end
end

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
parsed_gems_ruby, parsed_gems_jruby = parse_gemfiles("gemfiles/")
integrations = get_integration_names('lib/datadog/tracing/contrib/')

integration_json_mapping = {}

integrations.each do |integration|
  if excluded.include?(integration)
    next
  end
  # puts "integration: #{integration}"
  integration_name = mapping[integration] || integration

  min_version_jruby = parsed_gems_jruby[integration_name]
  min_version_ruby = parsed_gems_ruby[integration_name]

  # if min_version_ruby
  #   puts "minimum version of gem '#{integration_name} for Ruby': #{min_version_ruby}"
  # end
  # if min_version_jruby
  #   puts "minimum version of gem '#{integration_name} for JRuby': #{min_version_jruby}"
  # end

  # mapping jruby, ruby
  integration_json_mapping[integration] = [min_version_ruby, min_version_jruby]
  integration_json_mapping.replace(integration_json_mapping.sort.to_h)
end

File.write("minimum_gem_output.json", JSON.pretty_generate(integration_json_mapping))
