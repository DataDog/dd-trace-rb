RSpec.describe 'gem release process' do
  context 'datadog.gemspec' do
    subject(:gemspec) { Gem::Specification.load('datadog.gemspec') }

    context 'files' do
      # It's easy to forget to ship new files, especially when a new paradigm is
      # introduced (e.g. introducing native files requires the inclusion `ext/`)
      it 'includes all important files' do
        single_files_excluded = %r{
          ^
          (
            \.dockerignore
           |\.editorconfig
           |\.env
           |\.git-blame-ignore-revs
           |\.gitattributes
           |\.gitignore
           |\.gitlab-ci.yml
           |\.pryrc
           |\.rspec
           |\.rubocop.yml
           |\.rubocop_todo.yml
           |\.semgrepignore
           |\.simplecov
           |\.yardopts
           |ext/\.gitignore
           |ext/.*/.clang-format
           |Appraisals
           |CONTRIBUTING.md
           |Gemfile
           |Gemfile-.*
           |Rakefile
           |Matrixfile
           |Steepfile
           |datadog\.gemspec
           |docker-compose\.yml
           |shell\.nix
          )
          $
        }x

        directories_excluded = %r{
          ^(
            sig
            |spec
            |docs
            |\.circleci
            |\.github
            |\.gitlab
            |\.vscode
            |lib-injection
            |appraisal
            |benchmarks
            |gemfiles
            |integration
            |tasks
            |yard
            |vendor/rbs
          )/
        }x

        expect(gemspec.files)
          .to match_array(
            `git ls-files -z`
              .split("\x0")
              .reject { |f| f.match(directories_excluded) }
              .reject { |f| f.match(single_files_excluded) }
          )
      end
    end

    context 'lib injection dependencies' do
      it do
        file = Tempfile.new('Gemfile')

        begin
          file.write "source 'https://rubygems.org'\n"
          file.write "gem '#{gemspec.name}', path: '#{FileUtils.pwd}'\n"
          file.rewind

          gemfile = Bundler::Dsl.evaluate(file.path, nil, {})
          lock_file_parser = Bundler::LockfileParser.new(gemfile.to_lock)

          gem_version_mapping = lock_file_parser.specs.each_with_object({}) do |spec, hash|
            hash[spec.name] = spec.version.to_s
          end
        ensure
          file.close
          file.unlink
        end

        # Lib injection package pipeline should be updated to include the following gems
        expect(gem_version_mapping.keys).to contain_exactly(
          # This list MUST NOT derive from the `gemspec.dependencies`,
          # since it is used to alarm when dependencies  modified.
          'datadog',
          'debase-ruby_core_source',
          'ffi',
          'libdatadog',
          'libddwaf',
          'msgpack',
        )
      end
    end

    context 'licenses' do
      it 'returns dual licenses (BSD-3-Clause and Apache-2)' do
        expect(gemspec.licenses).to contain_exactly('BSD-3-Clause', 'Apache-2.0')
      end
    end

    describe '#metadata' do
      it do
        {
          'changelog_uri' => "https://github.com/DataDog/dd-trace-rb/blob/v#{gemspec.version}/CHANGELOG.md",
          'source_code_uri' => "https://github.com/DataDog/dd-trace-rb/tree/v#{gemspec.version}"
        }.each do |key, value|
          expect(gemspec.metadata[key]).to eq(value)
        end
      end

      # `allowed_push_host` is overwritten by automated scripts
      # in order to publish to another destination repository.
      context 'allowed_push_host' do
        it { expect(gemspec.metadata).to have_key('allowed_push_host') }

        it do
          expect(gemspec.metadata['allowed_push_host'])
            .to eq('https://rubygems.org')
            .or eq('https://rubygems.pkg.github.com/DataDog')
        end
      end
    end
  end
end
