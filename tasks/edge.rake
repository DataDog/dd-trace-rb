require 'open3'

require_relative 'appraisal_conversion'
require_relative 'runtime_matcher'

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
          { 'BUNDLE_GEMFILE' => gemfile.to_s },
          "bundle lock --update=#{gemspec_runtime_dependencies.map(&:name).join(' ')}"
        )

        puts output
      end
    end
  end

  desc 'Update groups with targeted dependencies'
  task :update do |_t, args|
    allowlist = {
      'stripe' => 'stripe',
      'elasticsearch' => 'elasticsearch',
      'opensearch' => 'opensearch-ruby',
      'rack' => 'rack',
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
          output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, "bundle lock --update=#{gem}")

          puts output
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
