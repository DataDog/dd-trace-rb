require 'spec_helper'

RSpec.describe 'Library benchmarks' do
  before { skip('Spec requires Ruby VM supporting fork') unless PlatformHelpers.supports_fork? }

  around do |example|
    ClimateControl.modify('VALIDATE_BENCHMARK' => 'true') do
      example.run
    end
  end

  benchmarks_to_validate = %w[
    library_gem_loading
  ]

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      it 'runs without raising errors' do
        expect_in_fork do
          load "./benchmarks/#{benchmark}.rb"
        end
      end
    end
  end

  # This test validates that we don't forget to add new benchmarks to benchmarks_to_validate
  it 'tests all expected benchmarks in the benchmarks folder' do
    all_benchmarks = Dir['./benchmarks/library_*'].map { |it| it.gsub('./benchmarks/', '').gsub('.rb', '') }

    expect(benchmarks_to_validate).to contain_exactly(*all_benchmarks)
  end
end
