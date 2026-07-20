require 'spec_helper'

begin
  require_relative '../../../tasks/dependency_audit'
  require_relative '../../../tasks/audit_remediation/relock_lockfile'
rescue LoadError
  # bundler-audit is only declared in the check group of gemfiles/ruby-4.0.gemfile;
  # on every other Ruby these modules are unavailable, so skip the whole suite
  # there instead of aborting the run at load time. See tasks/dependency_audit.rake
  # for the same guard applied to the rake task definition. dependency_audit is
  # required first so the LoadError is raised (and caught) before relock_lockfile
  # -- which itself only requires 'bundler' and would load fine either way --
  # ever gets a chance to define RelockLockfile.
end

if defined?(DependencyAudit) && defined?(RelockLockfile)
  require 'bundler/audit/database'
  require 'fileutils'
  require 'tmpdir'

  RSpec.describe RelockLockfile do
    before(:all) do
      Bundler::Audit::Database.update!(quiet: true)
      @database = Bundler::Audit::Database.new
    end

    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        example.run
      end
    end

    def copy_fixture(name)
      src = File.expand_path("../../fixtures/bundler_audit/#{name}", __dir__)
      dest = File.join(@tmpdir, name)
      FileUtils.cp_r(src, dest)
      dest
    end

    it 'resolves a lockfile with a loose constraint and clears the finding' do
      dir = copy_fixture('resolvable')
      lockfile = File.join(dir, 'Gemfile.lock')

      result = described_class.attempt(lockfile, ['rack'], database: @database, ignore: [])

      expect(result[:status]).to eq(RelockLockfile::RESOLVED)
      expect(result[:remaining_findings]).to be_empty
      expect(File.read(lockfile)).not_to include('rack (2.2.9)')
    end

    it 'leaves status unresolved when the constraint forces the same vulnerable version' do
      dir = copy_fixture('unresolvable')
      lockfile = File.join(dir, 'Gemfile.lock')

      result = described_class.attempt(lockfile, ['rack'], database: @database, ignore: [])

      expect(result[:status]).to eq(RelockLockfile::UNRESOLVED)
      expect(result[:remaining_findings]).not_to be_empty
      expect(File.read(lockfile)).to include('rack (2.0.4)')
    end

    it 'reports error status when bundler cannot resolve at all' do
      dir = copy_fixture('unresolvable')
      lockfile = File.join(dir, 'Gemfile.lock')
      gemfile = File.join(dir, 'Gemfile')
      File.write(gemfile, File.read(gemfile) + "\ngem 'this-gem-does-not-exist-anywhere'\n")

      result = described_class.attempt(lockfile, ['this-gem-does-not-exist-anywhere'], database: @database, ignore: [])

      expect(result[:status]).to eq(RelockLockfile::ERROR)
      expect(result[:error_message]).to be_a(String)
    end
  end
end
