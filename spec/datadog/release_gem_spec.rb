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
  end
end
