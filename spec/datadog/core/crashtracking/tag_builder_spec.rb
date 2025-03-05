require 'spec_helper'
require 'datadog/core/crashtracking/tag_builder'

RSpec.describe Datadog::Core::Crashtracking::TagBuilder do
  describe '.call' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    subject(:call) { described_class.call(settings) }

    it 'returns a hash with the tags to be attached to a crash report' do
      expect(call).to include(
        'host' => Datadog::Core::Environment::Socket.hostname,
        'process_id' => Process.pid.to_s,
        'runtime_engine' => RUBY_ENGINE,
        'runtime-id' => Datadog::Core::Environment::Identity.id,
        'runtime_platform' => RUBY_PLATFORM,
        'runtime_version' => RUBY_VERSION,
        'is_crash' => 'true',
        'language' => 'ruby',
        'library_version' => Datadog::Core::Environment::Identity.gem_datadog_version,
      )
    end

    describe 'unified service tagging' do
      [:env, :service, :version].each do |tag|
        context "when a #{tag} is defined" do
          before do
            settings.send(:"#{tag}=", 'expected_value')
          end

          it 'includes it as a tag' do
            expect(call).to include(tag.to_s => 'expected_value')
          end
        end

        context "when #{tag} is nil" do
          before do
            settings.send(:"#{tag}=", nil)
          end

          it do
            expect(call.keys).to_not include(tag.to_s)
          end
        end
      end
    end

    it 'includes the provided user tags' do
      settings.tags = { 'foo' => 'bar' }

      expect(call).to include('foo' => 'bar')
    end

    context 'when there is a conflict between user and metadata tags' do
      it 'overrides the user-provided tags' do
        settings.tags = { 'foo' => 'bar', 'version' => '1.0.0' }
        settings.version = '2.0.0'

        expect(call).to include('foo' => 'bar', 'version' => '2.0.0')
      end
    end

    context 'when user tag keys and values are not strings' do
      it 'encodes them as strings' do
        settings.tags = { :symbol_key => :symbol_value, nil => 'nil key', 'nil value' => nil, 12 => 34 }

        expect(call).to include('symbol_key' => 'symbol_value', '' => 'nil key', 'nil value' => '', '12' => '34')
      end
    end

    context 'when tagging key or value is not utf-8' do
      it 'converts them to utf-8' do
        settings.tags = { 'ascii-key'.encode(Encoding::ASCII) => 'ascii-value'.encode(Encoding::ASCII) }

        result = call

        result.each do |key, value|
          expect([key, value]).to all(have_attributes(encoding: Encoding::UTF_8))
        end
        expect(result).to include('ascii-key' => 'ascii-value')
      end
    end

    describe 'source code integration' do
      context 'when git environment is available' do
        before do
          allow(Datadog::Core::Environment::Git).to receive(:git_repository_url).and_return(
            'git_repository_url'
          )
          allow(Datadog::Core::Environment::Git).to receive(:git_commit_sha).and_return('git_commit_sha')
        end

        it 'includes the git repository URL and commit SHA' do
          expect(call).to include(
            'git.repository_url' => 'git_repository_url', 'git.commit.sha' => 'git_commit_sha'
          )
        end
      end

      context 'when git environment is not available' do
        before do
          allow(Datadog::Core::Environment::Git).to receive(:git_repository_url).and_return(nil)
          allow(Datadog::Core::Environment::Git).to receive(:git_commit_sha).and_return(nil)
        end

        it 'includes the git repository URL and commit SHA' do
          expect(call).to_not include('git.repository_url', 'git.commit.sha')
        end
      end
    end
  end
end
