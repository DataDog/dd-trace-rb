require 'spec_helper'
require 'datadog/core/environment/process'
require 'open3'

RSpec.describe Datadog::Core::Environment::Process do
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
        project_root_directory = Dir.pwd

        Dir.mktmpdir do |tmp_dir|
          Dir.chdir(tmp_dir) do
            Bundler.with_unbundled_env do
              _, stderr, status = Open3.capture3('rails new test_app --minimal --skip-active-record --skip-test --skip-keeps --skip-git --skip-docker')
              unless status.success? && File.exist?("test_app/Gemfile")
                skip("rails new failed: #{stderr}")
              end
            end

            File.open("test_app/Gemfile", 'a') do |file|
              file.puts "gem 'datadog', path: '#{project_root_directory}', require: false"
            end
            File.write("test_app/config/initializers/process_initializer.rb", <<-RUBY)
                        Rails.application.config.after_initialize do
                            require 'datadog/core/environment/process'
                            STDERR.puts "_dd.tags.process:\#{Datadog::Core::Environment::Process.serialized}"
                            STDERR.flush
                            Thread.new { Process.kill('TERM', Process.pid) }
                        end
            RUBY

            Bundler.with_unbundled_env do
              Dir.chdir("test_app") do
                _, _, _ = Open3.capture3('bundle install')
                _, err, _ = Open3.capture3('bundle exec rails s')
                expect(err).to include('entrypoint.workdir:test_app')
                expect(err).to include('entrypoint.type:script')
                expect(err).to include('entrypoint.name:rails')
                expect(err).to include('entrypoint.basedir:bin')
              end
            end
          end
        end
      end
    end
  end
end
