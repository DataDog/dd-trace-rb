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
    end
  end
end
