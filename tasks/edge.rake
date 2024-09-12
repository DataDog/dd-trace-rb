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

# rubocop:disable Metrics/BlockLength
namespace :edge do
  desc 'Update all the groups from the matrix'
  task :update do |_t, args|
    ruby_version = RUBY_VERSION[0..2]
    whitelist = {
      'stripe' => 'stripe',
      'elasticsearch' => 'elasticsearch',
      'opensearch' => 'opensearch-ruby',
      # Add more integrations here, when they are extracted to its own isolated group
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

      candidates.each do |group, _|
        gemfile = AppraisalConversion.to_bundle_gemfile(group)

        Bundler.with_unbundled_env do
          puts "======== Updating #{integration} in #{gemfile} ========\n"
          output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, "bundle lock --update=#{gem}")

          puts output
        end
      end
    end
  end

  desc 'Update the `latest` group from the matrix'
  task :latest do |_t, args|
    ruby_version = RUBY_VERSION[0..2]
    whitelist = {
      'stripe' => 'stripe',
      'elasticsearch' => 'elasticsearch',
      'opensearch' => 'opensearch-ruby',
      # Add more integrations here, when hey are extracted to its own isolated group
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

      candidates.each do |group, _|
        # ONLY pick the latest group
        next unless group.end_with?('-latest')

        gemfile = AppraisalConversion.to_bundle_gemfile(group)

        Bundler.with_unbundled_env do
          puts "======== Updating #{integration} in #{gemfile} ========\n"
          output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, "bundle lock --update=#{gem}")

          puts output
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
