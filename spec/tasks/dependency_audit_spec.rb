require 'spec_helper'

if Gem.loaded_specs.key?('bundler-audit')
  require_relative '../../tasks/dependency_auditing'
  require 'tmpdir'

  RSpec.describe DependencyAuditing do
    let(:fixtures) { 'spec/fixtures/bundler_audit' }
    let(:database) { Bundler::Audit::Database.new("#{fixtures}/advisory_db") }

    describe '.findings' do
      it 'returns high/critical findings for a vulnerable lockfile' do
        findings = described_class.findings(
          ["#{fixtures}/vulnerable.gemfile.lock"],
          database: database,
          ignore: [],
        )

        expect(findings).not_to be_empty
        expect(findings.map(&:criticality).uniq).to all(satisfy { |c| [:high, :critical].include?(c) })
        expect(findings.map(&:gem)).to include('rack')
        expect(findings.first).to have_attributes(lockfile: a_kind_of(String), gem: a_kind_of(String), version: a_kind_of(String), criticality: a_kind_of(Symbol), id: a_kind_of(String))
      end

      it 'returns nothing for a clean lockfile' do
        findings = described_class.findings(
          ["#{fixtures}/clean.gemfile.lock"],
          database: database,
          ignore: [],
        )

        expect(findings).to be_empty
      end

      it 'excludes advisories listed in ignore' do
        all = described_class.findings(
          ["#{fixtures}/vulnerable.gemfile.lock"], database: database, ignore: [],
        )
        ignored_id = all.first.id

        remaining = described_class.findings(
          ["#{fixtures}/vulnerable.gemfile.lock"], database: database, ignore: [ignored_id],
        )

        expect(remaining.map(&:id)).not_to include(ignored_id)
      end

      it 'excludes findings matching an entry in ignore_gem_versions' do
        all = described_class.findings(
          ["#{fixtures}/vulnerable.gemfile.lock"], database: database, ignore: [],
        )
        target = all.first

        remaining = described_class.findings(
          ["#{fixtures}/vulnerable.gemfile.lock"], database: database, ignore: [],
          ignore_gem_versions: [{'gem' => target.gem, 'version' => target.version}],
        )

        expect(remaining).not_to include(target)
      end

      it 'does not exclude a finding when only the gem matches but not the version' do
        all = described_class.findings(
          ["#{fixtures}/vulnerable.gemfile.lock"], database: database, ignore: [],
        )
        target = all.first

        remaining = described_class.findings(
          ["#{fixtures}/vulnerable.gemfile.lock"], database: database, ignore: [],
          ignore_gem_versions: [{'gem' => target.gem, 'version' => 'not-the-real-version'}],
        )

        expect(remaining).to include(target)
      end
    end

    describe '.load_ignore_gem_versions' do
      it 'returns an empty array when the config file does not exist' do
        expect(described_class.load_ignore_gem_versions('nonexistent.yml')).to eq([])
      end

      it 'returns the ignore_gem_versions entries from the config file' do
        Dir.mktmpdir do |dir|
          config_path = File.join(dir, '.bundler-audit.yml')
          File.write(config_path, <<~YAML)
            ignore: []
            ignore_gem_versions:
              - gem: rack
                version: 1.6.13
                reason: "test"
          YAML

          expect(described_class.load_ignore_gem_versions(config_path)).to eq(
            [{'gem' => 'rack', 'version' => '1.6.13', 'reason' => 'test'}],
          )
        end
      end
    end
  end
end
