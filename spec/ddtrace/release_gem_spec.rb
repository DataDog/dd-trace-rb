RSpec.describe 'gem release process' do
  context 'ddtrace.gemspec' do
    context 'files' do
      subject(:files) { Gem::Specification.load('ddtrace.gemspec').files }

      # It's easy to forget to ship new files, especially when a new paradigm is
      # introduced (e.g. introducing native files requires the inclusion `ext/`)
      it 'includes all important files' do
        single_files_excluded = %w[
          .dockerignore
          .editorconfig
          .env
          .git-blame-ignore-revs
          .gitattributes
          .gitignore
          .gitlab-ci.yml
          .pryrc
          .rspec
          .rubocop.yml
          .rubocop_todo.yml
          .simplecov
          .yardopts
          Appraisals
          CONTRIBUTING.md
          Gemfile
          Rakefile
          Steepfile
          ddtrace.gemspec
          docker-compose.yml
        ]

        directories_excluded = %r{^(sig|spec|docs|\.circleci|\.github|benchmarks|gemfiles|integration|tasks|sorbet|yard)/}

        expect(files)
          .to match_array(
            `git ls-files -z`
              .split("\x0")
              .reject { |f| f.match(directories_excluded) }
              .reject { |f| single_files_excluded.include?(f) }
          )
      end
    end
  end
end
