require 'spec_helper'
require 'datadog/core/environment/process'
require 'open3'

RSpec.describe Datadog::Core::Environment::Process do
  describe '::entrypoint_workdir' do
    subject(:entrypoint_workdir) { described_class.entrypoint_workdir }

    it { is_expected.to be_a_kind_of(String) }
  end

  describe '::entrypoint_type' do
    subject(:entrypoint_type) { described_class.entrypoint_type }

    it { is_expected.to be_a_kind_of(String) }
    it { is_expected.to eq(Datadog::Core::Environment::Ext::PROCESS_TYPE) }
  end

  describe '::entrypoint_name' do
    subject(:entrypoint_name) { described_class.entrypoint_name }

    it { is_expected.to be_a_kind_of(String) }
  end

  describe '::entrypoint_basedir' do
    subject(:entrypoint_basedir) { described_class.entrypoint_basedir }

    it { is_expected.to be_a_kind_of(String) }
  end

  describe '::server_type' do
    subject(:server_type) { described_class.server_type }

    it { is_expected.to be_a_kind_of(String) }
  end

  describe '::serialized' do
    subject(:serialized) { described_class.serialized }

    it { is_expected.to be_a_kind_of(String) }

    it 'returns the same object when called multiple times' do
      # Processes are fixed so no need to recompute this on each call
      first_call = described_class.serialized
      second_call = described_class.serialized
      expect(first_call).to equal(second_call)
    end
  end

  describe 'Scenario: Real applications' do
    context 'when running a real Rails application' do
      it 'detects Rails process information correctly' do
        Dir.mktmpdir do |tmp_dir|
          Dir.chdir(tmp_dir) do
            Bundler.with_unbundled_env do
              skip('rails gem could not be installed') unless system('gem install rails')
              unless system('rails new test_app --minimal --skip-test --skip-keeps --skip-git --skip-docker')
                skip('rails new command failed')
              end
            end
          end
          File.open("#{tmp_dir}/test_app/Gemfile", 'a') do |file|
            file.puts "gem 'datadog', path: '#{Dir.pwd}', require: false"
          end
          File.write("#{tmp_dir}/test_app/config/initializers/process_initializer.rb", <<-RUBY)
                      Rails.application.config.after_initialize do
                          require 'datadog/core/environment/process'
                          STDERR.puts "entrypoint_workdir:\#{Datadog::Core::Environment::Process.entrypoint_workdir}"
                          STDERR.puts "entrypoint_type:\#{Datadog::Core::Environment::Process.entrypoint_type}"
                          STDERR.puts "entrypoint_name:\#{Datadog::Core::Environment::Process.entrypoint_name}"
                          STDERR.puts "entrypoint_basedir:\#{Datadog::Core::Environment::Process.entrypoint_basedir}"
                          STDERR.puts "server_type:\#{Datadog::Core::Environment::Process.server_type}"
                          STDERR.puts "_dd.tags.process:\#{Datadog::Core::Environment::Process.serialized}"
                          STDERR.flush
                          Thread.new { sleep 1; Process.kill('TERM', Process.pid)}#{' '}
                      end
          RUBY
          Bundler.with_unbundled_env do
            Dir.chdir("#{tmp_dir}/test_app") do
              _, _, _ = Open3.capture3('bundle install')
              _, err, _ = Open3.capture3('bundle exec rails s')
              expect(err).to include('entrypoint_workdir:test_app')
              expect(err).to include('entrypoint_type:script')
              expect(err).to include('entrypoint_name:rails')
              basedir_test = tmp_dir.sub(%r{^/}, '')
              expect(err).to include("entrypoint_basedir:#{basedir_test}/test_app/bin")
              expect(err).to include('server_type:placeholder')
              expected_tags = "entrypoint.workdir:test_app,entrypoint.name:rails,entrypoint.basedir:#{basedir_test}/test_app/bin,entrypoint.type:script,server.type:placeholder"
              expect(err).to include("_dd.tags.process:#{expected_tags}")
            end
          end
        end
      end
    end
  end
end
