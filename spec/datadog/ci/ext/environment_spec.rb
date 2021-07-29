require 'datadog/ci/spec_helper'

require 'json'
require 'datadog/ci/ext/environment'

RSpec.describe Datadog::CI::Ext::Environment do
  FIXTURE_DIR = "#{File.dirname(__FILE__)}/fixtures/" # rubocop:disable all

  describe '.tags' do
    subject(:tags) do
      ClimateControl.modify(environment_variables) { described_class.tags(env) }
    end

    let(:env) { {} }
    let(:environment_variables) { {} }

    shared_context 'with git fixture' do |git_fixture|
      let(:environment_variables) do
        super().merge('GIT_DIR' => "#{FIXTURE_DIR}/git/#{git_fixture}", 'GIT_WORK_TREE' => "#{FIXTURE_DIR}/git/")
      end
    end

    shared_context 'without git installed' do
      before { allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT, 'No such file or directory - git') }
    end

    Dir.glob("#{FIXTURE_DIR}/ci/*.json").sort.each do |filename|
      # Parse each CI provider file
      File.open(filename) do |f|
        context "for fixture #{File.basename(filename)}" do
          # Create a context for each example inside the JSON fixture file
          JSON.parse(f.read).each_with_index do |(env, tags), i|
            context "##{i}" do
              # Modify HOME so that '~' expansion matches CI home directory.
              let(:environment_variables) { super().merge('HOME' => env['HOME']) }
              let(:env) { env }

              context 'with git information' do
                include_context 'with git fixture', 'gitdir_with_commit'

                it 'matches CI tags, with git fallback information' do
                  is_expected
                    .to eq(
                      {
                        'ci.workspace_path' => "#{Dir.pwd}/spec/datadog/ci/ext/fixtures/git",
                        'git.branch' => 'master',
                        'git.commit.author.date' => '2011-02-16T13:00:00+00:00',
                        'git.commit.author.email' => 'bot@friendly.test',
                        'git.commit.author.name' => 'Friendly bot',
                        'git.commit.committer.date' => '2021-06-17T18:35:10+00:00',
                        'git.commit.committer.email' => 'marco.costa@datadoghq.com',
                        'git.commit.committer.name' => 'Marco Costa',
                        'git.commit.message' => 'First commit!',
                        'git.commit.sha' => '9322ca1d57975b49b8c00b449d21b06660ce8b5b',
                        'git.repository_url' => 'https://datadoghq.com/git/test.git'
                      }.merge(tags)
                    )
                end
              end

              context 'without git information' do
                include_context 'without git installed'

                it 'matches only CI tags' do
                  is_expected.to eq(tags)
                end
              end
            end
          end
        end
      end
    end

    context 'inside a git directory' do
      context 'with a newly created git repository' do
        include_context 'with git fixture', 'gitdir_empty'
        it 'matches tags' do
          is_expected.to eq('ci.workspace_path' => "#{Dir.pwd}/spec/datadog/ci/ext/fixtures/git")
        end
      end

      context 'with a git repository with a commit' do
        include_context 'with git fixture', 'gitdir_with_commit'
        it 'matches tags' do
          is_expected.to eq(
            'ci.workspace_path' => "#{Dir.pwd}/spec/datadog/ci/ext/fixtures/git",
            'git.branch' => 'master',
            'git.commit.author.date' => '2011-02-16T13:00:00+00:00',
            'git.commit.author.email' => 'bot@friendly.test',
            'git.commit.author.name' => 'Friendly bot',
            'git.commit.committer.date' => '2021-06-17T18:35:10+00:00',
            'git.commit.committer.email' => 'marco.costa@datadoghq.com',
            'git.commit.committer.name' => 'Marco Costa',
            'git.commit.message' => 'First commit!',
            'git.commit.sha' => '9322ca1d57975b49b8c00b449d21b06660ce8b5b',
            'git.repository_url' => 'https://datadoghq.com/git/test.git'
          )
        end
      end

      context 'not inside a git repository' do
        let(:environment_variables) { { 'GIT_DIR' => './tmp/not-a-git-dir' } }

        it 'does not fail' do
          is_expected.to eq({})
        end
      end

      context 'without git installed nor CI information' do
        include_context 'without git installed'

        it 'does not fail' do
          allow(Datadog.logger).to receive(:debug)

          is_expected.to eq({})

          expect(Datadog.logger).to have_received(:debug).with(/No such file or directory - git/).at_least(1).time
        end
      end
    end
  end
end
