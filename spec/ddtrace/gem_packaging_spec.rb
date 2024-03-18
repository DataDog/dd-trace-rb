require 'rubygems'
require 'rubygems/package'
require 'rubygems/package/tar_reader'

RSpec.describe 'gem release process (after packaging)' do
  # TODO: This will need to be updated for the 2.0 branch
  let(:gem_name) { 'ddtrace' }
  let(:gem_version) { DDTrace::VERSION::STRING }
  let(:packaged_gem_file) { "pkg/#{gem_name}-#{gem_version}.gem" }
  let(:executable_permissions) { ['bin/ddprofrb', 'bin/ddtracerb'] }

  it 'sets the right permissions on the gem files' do
    gem_files = Dir.glob('pkg/*.gem')
    expect(gem_files).to include(packaged_gem_file)

    gem_files.each do |gem_file|
      Gem::Package::TarReader.new(File.open(gem_file)) do |tar|
        data = tar.find { |entry| entry.header.name == 'data.tar.gz' }

        Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(data.read))) do |data_tar|
          data_tar.each do |entry|
            filename = entry.header.name
            octal_permissions = entry.header.mode.to_s(8)[-3..-1]

            expected_permissions = executable_permissions.include?(filename) ? '755' : '644'

            expect(octal_permissions).to eq(expected_permissions),
              "Unexpected permissions for #{filename} inside #{gem_file} (got #{octal_permissions}, " \
              "expected #{expected_permissions})"
          end
        end
      end
    end
  end
end
