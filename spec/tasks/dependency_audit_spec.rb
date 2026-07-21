require 'spec_helper'

if Gem.loaded_specs.key?('bundler-audit')
  require_relative '../../tasks/dependency_audit'

  RSpec.describe DependencyAudit do
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
        expect(findings.map { |f| f[:criticality] }.uniq).to all(satisfy { |c| [:high, :critical].include?(c) })
        expect(findings.map { |f| f[:gem] }).to include('rack')
        expect(findings.first).to include(:lockfile, :gem, :version, :criticality, :id)
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
        ignored_id = all.first[:id]

        remaining = described_class.findings(
          ["#{fixtures}/vulnerable.gemfile.lock"], database: database, ignore: [ignored_id],
        )

        expect(remaining.map { |f| f[:id] }).not_to include(ignored_id)
      end
    end
  end
end
