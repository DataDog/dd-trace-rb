require "datadog/di/spec_helper"
require "datadog/di/utils"

RSpec.describe Datadog::DI::Utils do
  di_test

  describe '.path_matches_suffix?' do
    # NB; when updating this list also add to the list in
    # path_can_match_spec? test below.
    [
      ['exact match - absolute path', '/foo/bar.rb', '/foo/bar.rb', true],
      # Suffix matching is only applicable to relative paths.
      ['absolute path is a suffix', '/bar.rb', '/foo/bar.rb', false],
      ['suffix - multiple path components', 'foo/bar.rb', '/foo/bar.rb', true],
      ['suffix - at basename', 'bar.rb', '/foo/bar.rb', true],
      ['suffix - not at path component boundary', 'ar.rb', '/foo/bar.rb', false],
      ['extra leading slash in file', '//foo/bar.rb', '/foo/bar.rb', false],
      ['extra slash in the middle of file', 'foo//bar.rb', '/foo/bar.rb', false],
      ['nothing in common', 'blah.rb', '/foo/bar.rb', false],
      ['path is a suffix of file', '/a/foo/bar.rb', '/foo/bar.rb', false],

      # We expect path to always be an absolute path.
      ['path is relative', 'bar.rb', 'bar.rb', false],
    ].each do |name, suffix_, path_, result_|
      suffix, path, result = suffix_, path_, result_

      context name do
        it "is #{result}" do
          expect(described_class.path_matches_suffix?(path, suffix)).to be result
        end
      end
    end
  end

  describe '.path_can_match_spec?' do
    # NB; when updating this list also add to the list in
    # path_matches_suffix? test above.
    [
      ['exact match - absolute path', '/foo/bar.rb', '/foo/bar.rb', true],
      # Prefixes of suffix are removed until there is a match
      ['absolute path is a suffix', '/bar.rb', '/foo/bar.rb', true],
      # ... but not if basename does not match
      ['absolute path is a suffix', '/bar.rb', '/foo/bar1.rb', false],
      ['suffix - multiple path components', 'foo/bar.rb', '/foo/bar.rb', true],
      ['suffix - at basename', 'bar.rb', '/foo/bar.rb', true],
      ['suffix - not at path component boundary', 'ar.rb', '/foo/bar.rb', false],
      # Extra leading slashes are removed
      ['extra leading slash in file', '//foo/bar.rb', '/foo/bar.rb', true],
      # Extra slashes in the middle are also removed
      ['extra slash in the middle of file', 'foo//bar.rb', '/foo/bar.rb', true],
      ['nothing in common', 'blah.rb', '/foo/bar.rb', false],
      ['path is a suffix of file', '/a/foo/bar.rb', '/foo/bar.rb', true],

      # We expect path to always be an absolute path.
      ['path is relative', 'bar.rb', 'bar.rb', false],
    ].each do |name, suffix_, path_, result_|
      suffix, path, result = suffix_, path_, result_

      context name do
        it "is #{result}" do
          expect(described_class.path_can_match_spec?(path, suffix)).to be result
        end
      end
    end
  end
end
