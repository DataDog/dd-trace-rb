require "open3"
require "set"

require_relative "appraisal_conversion"
require_relative "edge_dependencies"
require_relative "runtime_matcher"

# rubocop:disable Metrics/BlockLength
namespace :edge do
  desc "Update all the groups with gemspec dependencies"
  task :gemspec do
    candidates = Set.new

    TEST_METADATA.each do |_, metadata|
      metadata.each do |group, rubies|
        candidates << group if RuntimeMatcher.match?(rubies)
      end
    end

    gemspec_runtime_dependencies = Gem::Specification.load("datadog.gemspec").dependencies

    candidates.each do |group|
      next if group.empty?

      gemfile = AppraisalConversion.to_bundle_gemfile(group)

      Bundler.with_unbundled_env do
        output, = Open3.capture2e(
          {"BUNDLE_GEMFILE" => gemfile.to_s},
          "bundle lock --update #{gemspec_runtime_dependencies.map(&:name).join(" ")}",
        )

        puts output
      end
    end
  end

  desc "Update groups with targeted dependencies"
  task :update do |_t, args|
    allowlist = EdgeDependencies::ALLOWLIST
    allowlist = allowlist.slice(*args.extras) if args.extras.any?

    allowlist.each do |integration, gems|
      candidates = TEST_METADATA.fetch(integration).select do |_, rubies|
        RuntimeMatcher.match?(rubies)
      end

      candidates.each do |group, _|
        gemfile = AppraisalConversion.to_bundle_gemfile(group)

        # A group's gems aren't all present in every ruby-version gemfile (e.g. faraday-follow_redirects
        # is latest-only); `bundle lock --update` errors out if asked to update a gem that isn't there.
        lockfile_specs = Bundler::LockfileParser.new(Bundler.read_file("#{gemfile}.lock")).specs.map(&:name)
        gems_to_update = Array(gems).select { |gem| lockfile_specs.include?(gem) }

        next if gems_to_update.empty?

        update_flags = gems_to_update.map { |gem| "--update=#{gem}" }.join(" ")

        Bundler.with_unbundled_env do
          output, status = Open3.capture2e({"BUNDLE_GEMFILE" => gemfile.to_s}, "bundle lock #{update_flags}")

          puts output
          raise "bundle lock failed for #{gemfile}" unless status.success?
        end
      end
    end
  end

  desc "Print the markdown table of allowlisted gems whose lockfile version changed since a git revision"
  task :report, [:base] do |_t, args|
    puts EdgeDependencies.report(base: args[:base] || "HEAD")
  end
end
# rubocop:enable Metrics/BlockLength
