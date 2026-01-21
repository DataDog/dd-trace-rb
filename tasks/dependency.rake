require_relative 'appraisal_conversion'

namespace :dependency do
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
  task :generate do |t, args|
    sh 'bundle exec ruby appraisal/generate.rb'
  end

  task :exec do |t, args|
    command = args.extras.any? ? args.extras.first : 'bundle version'

    gemfiles = Dir.glob(AppraisalConversion.gemfile_pattern, base: AppraisalConversion.root_path)

    gemfiles.each do |gemfile|
      Bundler.with_unbundled_env do
        sh({'BUNDLE_GEMFILE' => gemfile.to_s}, command)
      end
    end
  end

  # Replacement for `bundle exec appraisal install`
  # Generates lockfiles and runs dependencies gemspecs.
  # `bundle install` is used instead of `bundle lock` because
  # it checks each gem's gemspec requirements (e.g. required_ruby_version, required_rubygems_version).
  #
  # Usage:
  #   rake dependency:install          # Install all gemfiles
  #   rake dependency:install[frozen]  # Install with BUNDLE_FROZEN=true (for CI cache)
  desc "Install dependencies for #{AppraisalConversion.runtime_identifier}"
  task :install, [:frozen] do |t, args|
    frozen = args[:frozen] == 'frozen'
    gemfiles = Dir.glob(AppraisalConversion.gemfile_pattern).sort
    total = gemfiles.size

    gemfiles.each_with_index do |gemfile, index|
      puts "  # [#{index + 1}/#{total}] #{File.basename(gemfile)}"

      env = {'BUNDLE_GEMFILE' => gemfile}
      env['BUNDLE_FROZEN'] = 'true' if frozen
      cmd = frozen ? 'bundle check || bundle install' : 'bundle install'

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      AppraisalConversion.with_retry do
        Bundler.with_unbundled_env { sh(env, cmd) }
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      puts "  # [#{index + 1}/#{total}] #{File.basename(gemfile)}: Finished in #{elapsed.round(1)}s"
    end
  end


  desc "Show gems not needed by any Gemfile for this Ruby version (dry-run)"
  task :clean_unused_gems do
    require 'set'
    require 'open3'

    gemfiles = ['Gemfile'] + Dir.glob(AppraisalConversion.gemfile_pattern)

    puts "Checking #{gemfiles.size} gemfiles for stale gems..."

    threads = gemfiles.map do |gf|
      Thread.new(gf) do |gemfile|
        output, _ = Bundler.with_unbundled_env do
          Open3.capture2({ 'BUNDLE_GEMFILE' => gemfile }, 'bundle', 'clean', '--dry-run')
        end

        stale = output.lines
          .grep(/^Would have removed/)
          .map { |line| line.delete_prefix('Would have removed ').strip }

        Set.new(stale)
      end
    end

    stale_per_gemfile = threads.map(&:value)
    truly_stale = stale_per_gemfile.reduce(:&) || Set.new

    puts "\nGems not needed by ANY gemfile: #{truly_stale.size}"
    truly_stale.sort.each { |g| puts "  #{g}" }
  end
end
