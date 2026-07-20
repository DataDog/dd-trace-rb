require 'spec_helper'

if Gem.loaded_specs.key?('bundler-audit')
  require_relative '../../tasks/dependency_audit'

  RSpec.describe DependencyAudit do
    # Uses the real advisory database; update it once for the suite so results
    # are deterministic within the run. Requires git + network.
    before(:all) do
      require 'bundler/audit/database'
      Bundler::Audit::Database.update!(quiet: true)
      @database = Bundler::Audit::Database.new
    end

    let(:fixtures) { 'spec/fixtures/bundler_audit' }

    describe '.high_critical_findings' do
      it 'returns high/critical findings for a vulnerable lockfile' do
        findings = described_class.high_critical_findings(
          ["#{fixtures}/vulnerable.gemfile.lock"],
          database: @database,
          ignore: [],
        )

        expect(findings).not_to be_empty
        expect(findings.map { |f| f[:criticality] }.uniq).to all(satisfy { |c| [:high, :critical].include?(c) })
        expect(findings.map { |f| f[:gem] }).to include('rack')
        expect(findings.first).to include(:lockfile, :gem, :version, :criticality, :id)
      end

      it 'returns nothing for a clean lockfile' do
        findings = described_class.high_critical_findings(
          ["#{fixtures}/clean.gemfile.lock"],
          database: @database,
          ignore: [],
        )

        expect(findings).to be_empty
      end

      it 'excludes advisories listed in ignore' do
        all = described_class.high_critical_findings(
          ["#{fixtures}/vulnerable.gemfile.lock"], database: @database, ignore: [],
        )
        ignored_id = all.first[:id]

        remaining = described_class.high_critical_findings(
          ["#{fixtures}/vulnerable.gemfile.lock"], database: @database, ignore: [ignored_id],
        )

        expect(remaining.map { |f| f[:id] }).not_to include(ignored_id)
      end
    end
  end
end
