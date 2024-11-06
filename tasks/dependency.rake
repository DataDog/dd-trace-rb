require 'open3'

require_relative 'appraisal_conversion'

namespace :dependency do
  gemfiles = Dir.glob(AppraisalConversion.gemfile_pattern)

  # Replacement for `bundle exec appraisal list`
  desc "List dependencies for #{AppraisalConversion.runtime_identifier}"
  task :list do
    puts "Ahoy! Here is a list of gemfiles you are looking for:\n\n"

    puts "========================================\n"
    puts gemfiles
    puts "========================================\n"

    puts "You can do a bunch of cool stuff by assign it to the BUNDLE_GEMFILE environment variable, like:\n"
    puts "`BUNDLE_GEMFILE=#{gemfiles.sample} bundle install`\n\n"
  end

  namespace :lock do
    gemfiles.each do |gemfile|
      # desc "Lock dependencies for #{gemfile}"
      task gemfile do
        Bundler.with_unbundled_env do
          command = +'bundle lock'
          command << ' --add-platform x86_64-linux aarch64-linux' unless RUBY_PLATFORM == 'java'
          output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, command)

          puts output
        end
      end
    end
  end

  # WHY can't we use `multitask` here?
  #
  # Running bundler in parallel has various race conditions
  #
  # Race condition with the file system, particularly worse with JRuby.
  # For instance, `Errno::ENOENT: No such file or directory - bundle` is raised with JRuby 9.2

  # Even with CRuby, `simplcov` declaration with `github` in Gemfile causes
  # race condition for the local gem cache with the following error:

  # ```
  # [/usr/local/bundle/bundler/gems/simplecov-3bb6b7ee58bf/simplecov.gemspec] isn't a Gem::Specification (NilClass instead).
  # ```

  # and

  # ```
  # fatal: Unable to create '/usr/local/bundle/bundler/gems/simplecov-3bb6b7ee58bf/.git/index.lock': File exists.
  # Another git process seems to be running in this repository, e.g.
  # an editor opened by 'git commit'. Please make sure all processes
  # are terminated then try again. If it still fails, a git process
  # may have crashed in this repository earlier:
  # remove the file manually to continue.
  # ```
  desc "Lock dependencies for #{AppraisalConversion.runtime_identifier}"
  task :lock => gemfiles.map { |gemfile| "lock:#{gemfile}" }

  namespace :install do
    gemfiles.each do |gemfile|
      # desc "Install dependencies for #{gemfile}"
      task gemfile => "lock:#{gemfile}" do
        Bundler.with_unbundled_env do
          output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, "bundle check || bundle install")

          puts output
        end
      end
    end
  end

  # Replacement for `bundle exec appraisal install`
  desc "Install dependencies for #{AppraisalConversion.runtime_identifier}"
  task :install => gemfiles.map { |gemfile| "install:#{gemfile}" }
end
