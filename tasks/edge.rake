# frozen_string_literal: true

require 'open3'
require 'pathname'

# This module translates our custom mapping between appraisal and bundler.
#
# It cannot be included into `Appraisal` file, because it was invoked via `instance_eval`.
module AppraisalConversion
  module_function

  @gemfile_dir = 'gemfiles'
  @definition_dir = 'appraisal'

  def to_bundle_gemfile(group)
    gemfile = "#{runtime_identifier}_#{group}.gemfile".tr('-', '_')
    path = root_path.join(@gemfile_dir, gemfile)

    if path.exist?
      path.to_s
    else
      raise "Gemfile not found at #{path}"
    end
  end

  def definition
    path = root_path.join(@definition_dir, "#{runtime_identifier}.rb")

    if path.exist?
      path.to_s
    else
      raise "Definition not found at #{path}"
    end
  end

  def runtime_identifier
    major, minor, = Gem::Version.new(RUBY_ENGINE_VERSION).segments
    "#{RUBY_ENGINE}-#{major}.#{minor}"
  end

  def root_path
    Pathname.pwd
  end
end

namespace :edge do
  desc 'Update edge build for current ruby runtime'
  task :update do |_t, args|
    ruby_version = RUBY_VERSION[0..2]
    whitelist = {
      'aws' => 'aws-sdk',
      'elasticsearch' => 'elasticsearch',
      'graphql' => 'graphql',
      'hanami' => 'hanami',
      'opensearch' => 'opensearch-ruby',
      'opentelemetry-sdk' => 'opentelemetry',
      'rack' => 'rack',
      'rails' => 'rails',
      'redis' => 'redis',
      'resque' => 'resque',
      'sinatra' => 'sinatra',
      'stripe' => 'stripe',
      # TODO: Add more integrations here, when they are extracted to its own isolated group
    }

    whitelist = whitelist.slice(*args.extras) if args.extras.any?

    whitelist.each do |integration, gem|
      candidates = TEST_METADATA.fetch(integration).select do |_, rubies|
        if RUBY_PLATFORM == 'java'
          rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
        else
          rubies.include?("✅ #{ruby_version}")
        end
      end

      gemfiles = candidates.keys.map do |group|
        AppraisalConversion.to_bundle_gemfile(group)
      end

      gemfiles.each do |gemfile|
        Bundler.with_unbundled_env do
          puts "======== Updating #{integration} in #{gemfile} ========\n"
          output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, "bundle lock --update=#{gem}")

          puts output
        end
      end
    end
  end
end
