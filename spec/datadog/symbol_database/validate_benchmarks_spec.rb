require 'spec_helper'

RSpec.describe 'Symbol Database benchmarks' do
  before { skip('Spec requires Ruby VM supporting fork') unless PlatformHelpers.supports_fork? }

  with_env 'VALIDATE_BENCHMARK' => 'true'

  benchmarks_to_validate = %w[
    symbol_database_extraction
    symbol_database_background_impact
    symbol_database_baseline_matrix
  ]

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      it 'runs without raising errors' do
        # DIAGNOSTIC: bump timeout and print fork stderr on success so the
        # baseline_matrix benchmark's per-phase timing trace surfaces in CI logs.
        # Default expect_in_fork captures stderr into a tempfile and discards it
        # on success, hiding the trace. Restore the default once CI timing is
        # understood.
        expect_in_fork(
          timeout_seconds: 60,
          fork_expectations: proc { |status:, stdout:, stderr:|
            warn "=== fork stderr from #{benchmark} ==="
            warn stderr
            warn "=== end fork stderr from #{benchmark} ==="
            expect(status && status.success?).to be(true),
              "Status:#{status.inspect} STDOUT:`#{stdout}` STDERR:`#{stderr}`"
          }
        ) do
          load "./benchmarks/#{benchmark}.rb"
        end
      end
    end
  end

  # This test validates that we don't forget to add new benchmarks to benchmarks_to_validate
  it 'tests all expected benchmarks in the benchmarks folder' do
    all_benchmarks = Dir['./benchmarks/symbol_database_*'].map { |it| it.gsub('./benchmarks/', '').gsub('.rb', '') }

    expect(benchmarks_to_validate).to contain_exactly(*all_benchmarks)
  end
end
