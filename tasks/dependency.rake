require_relative "appraisal_conversion"
require_relative "prelock"
require_relative "security_capabilities"

namespace :dependency do
  # Call outside `Bundler.with_unbundled_env`, which clears `BUNDLE_*` from `ENV`
  # for the duration of its block.
  def bundle_env(gemfile)
    env = {"BUNDLE_GEMFILE" => gemfile.to_s}
    cooldown = ENV["BUNDLE_COOLDOWN"]
    env["BUNDLE_COOLDOWN"] = cooldown if cooldown
    env
  end

  # Resolving from scratch lets cooldown exclude a fresh Datadog-owned gem whose
  # `~>` pin has no older fallback. Seeding pins it first; cooldown never
  # retracts a pinned version.
  def seed_lockfile(gemfile)
    lockfile = "#{gemfile}.lock"
    return if File.exist?(lockfile)

    parent_lockfile = "#{AppraisalConversion.parent_gemfile}.lock"
    return unless File.exist?(parent_lockfile)

    cp(parent_lockfile, lockfile)
  end

  desc "Regenerate, lock, and propagate dependencies for #{AppraisalConversion.runtime_identifier}"
  task all: [:generate, :lock, :propagate]

  desc "Find gemfiles for #{AppraisalConversion.runtime_identifier} with no matching appraisal definition"
  task :orphans do
    sh "bundle exec ruby appraisal/orphans.rb"
  end

  # Replacement for `bundle exec appraisal list`
  desc "List dependencies for #{AppraisalConversion.runtime_identifier}"
  task :list do |t, args|
    pattern = args.extras.any? ? args.extras : AppraisalConversion.gemfile_pattern

    gemfiles = Dir.glob(pattern, base: AppraisalConversion.root_path)

    puts "Ahoy! Here is a list of gemfiles you are looking for:\n\n"

    puts "========================================\n"
    puts gemfiles
    puts "========================================\n"

    puts "You can do a bunch of cool stuff by assigning a gemfile path to the BUNDLE_GEMFILE environment variable, like:\n"
    puts "`BUNDLE_GEMFILE=#{gemfiles.sample} bundle install`\n\n"
  end

  # Replacement for `bundle exec appraisal generate`
  desc "Generate dependencies for #{AppraisalConversion.runtime_identifier}"
  task :generate do |_, _|
    sh "bundle exec ruby appraisal/generate.rb"
  end

  desc "Run an arbitrary command across every appraisal gemfile for #{AppraisalConversion.runtime_identifier}"
  task :exec do |_t, args|
    command = args.extras.any? ? args.extras.first : "bundle version"

    gemfiles = Dir.glob(AppraisalConversion.gemfile_pattern)

    gemfiles.each do |gemfile|
      env = bundle_env(gemfile)

      Bundler.with_unbundled_env do
        sh(env, command)
      end
    end
  end

  # Replacement for `bundle exec appraisal bundle lock`
  desc "Lock dependencies for #{AppraisalConversion.runtime_identifier}"
  task :lock do |_t, args|
    pattern = args.extras.any? ? args.extras : AppraisalConversion.gemfile_pattern

    gemfiles = Dir.glob(pattern)
    checksum_eligible = SecurityCapabilities.for_version(RUBY_VERSION)[:checksum]

    gemfiles.each do |gemfile|
      seed_lockfile(gemfile)
      Prelock.call(gemfile)
      env = bundle_env(gemfile)

      Bundler.with_unbundled_env do
        command = +"bundle lock"
        command << " --add-platform x86_64-linux aarch64-linux arm64-darwin x86_64-darwin"
        command << " --add-checksums" if checksum_eligible
        sh(env, command)
      end
    end
  end

  desc "Lock Datadog-owned gems without cooldown for one gemfile, when the cooled lock could not resolve them"
  task :prelock do |_t, args|
    Prelock.call(args.extras.first || Bundler.default_gemfile)
  end

  desc "Propagate parent lockfile versions into appraisal lockfiles for #{AppraisalConversion.runtime_identifier}"
  task :propagate do
    parent_lockfile = "#{AppraisalConversion.parent_gemfile}.lock"
    raise "Parent lockfile #{parent_lockfile} not found" unless File.exist?(parent_lockfile)

    parent_versions = Bundler::LockfileParser.new(File.read(parent_lockfile)).specs
      .each_with_object({}) { |spec, hash| hash[spec.name] = spec.version.to_s }

    gemfiles = Dir.glob(AppraisalConversion.gemfile_pattern)

    gemfiles.each do |gemfile|
      lockfile = "#{gemfile}.lock"
      next unless File.exist?(lockfile)

      appraisal_specs = Bundler::LockfileParser.new(File.read(lockfile)).specs
      drifted = appraisal_specs.select do |spec|
        parent_versions[spec.name] && parent_versions[spec.name] != spec.version.to_s
      end.map(&:name).uniq

      next if drifted.empty?

      env = bundle_env(gemfile)

      Bundler.with_unbundled_env do
        sh(env, "bundle lock --update #{drifted.join(" ")}")
      end
    end
  end

  # Replacement for `bundle exec appraisal install`
  desc "Install dependencies for #{AppraisalConversion.runtime_identifier}"
  task install: :lock do |_t, args|
    pattern = args.extras.any? ? args.extras : AppraisalConversion.gemfile_pattern

    gemfiles = Dir.glob(pattern)

    gemfiles.each do |gemfile|
      env = bundle_env(gemfile)

      Bundler.with_unbundled_env do
        sh(env, "bundle check || bundle install")
      end
    end
  end
end
