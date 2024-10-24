require 'open3'

require_relative 'appraisal_conversion'

task :dep => :dependency
task :dependency => %w[dependency:lock]
namespace :dependency do
  # rubocop:disable Style/MultilineBlockChain
  Dir.glob(AppraisalConversion.gemfile_pattern).each do |gemfile|
    # desc "Lock the dependencies for #{gemfile}"
    task gemfile do
      Bundler.with_unbundled_env do
        command = +'bundle lock'
        command << ' --add-platform x86_64-linux aarch64-linux' unless RUBY_PLATFORM == 'java'
        output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, command)

        puts output
      end
    end
  end.tap do |gemfiles|
    desc "Lock the dependencies for #{AppraisalConversion.runtime_identifier}"
    # WHY can't we use `multitask :lock => gemfiles` here?
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
    task :lock => gemfiles
  end
  # rubocop:enable Style/MultilineBlockChain
end
