require 'spec_helper'

require 'benchmark'
require 'ddtrace/augmentation/shim'

RSpec.describe 'Datadog::Shim performance' do
  let(:iterations) { 1_000_000 }

  before(:each) { skip('Performance test does not run in CI.') }

  describe Datadog::Shim do
    let(:test_class) do
      stub_const('TestClass', Class.new do
        def foo
          :foo
        end
      end)
    end
    let(:object) { test_class.new }

    shared_context 'Shim#wrap_method! with block' do
      let(:wrap_block_double) do
        Datadog::Shim.new(object) do |shim|
          shim.wrap_method!(:foo) do |original, *args, &block|
            original.call(*args, &block)
          end
        end
      end
    end

    shared_context 'Shim#wrap_method! without args' do
      let(:wrap_no_args_double) do
        Datadog::Shim.new(object) do |shim|
          shim.wrap_method!(:foo, &:call)
        end
      end
    end

    shared_context 'Shim#override_method! with block' do
      let(:override_block_double) do
        Datadog::Shim.new(object) do |shim|
          shim.override_method!(:foo) do |*args, &block|
            shim_target.foo(*args, &block)
          end
        end
      end
    end

    shared_context 'Shim#override_method! without args' do
      let(:override_no_args_double) do
        Datadog::Shim.new(object) do |shim|
          shim.override_method!(:foo) do
            shim_target.foo
          end
        end
      end
    end

    describe 'benchmark' do
      include_context 'Shim#wrap_method! with block'
      include_context 'Shim#wrap_method! without args'
      include_context 'Shim#override_method! with block'
      include_context 'Shim#override_method! without args'

      let(:variables) do
        {
          control: object,
          wrap_block: wrap_block_double,
          wrap_no_args: wrap_no_args_double,
          override_block: override_block_double,
          override_no_args: override_no_args_double
        }
      end

      describe 'baseline comparison' do
        def run_comparison
          variables.inject({}) do |results, (k, v)|
            results.tap do
              results[k] = Benchmark.measure do
                iterations.times { raise RuntimeError if v.foo != :foo }
              end
            end
          end
        end

        let(:results) do
          # Do a warm-up
          run_comparison

          # Then keep the second set of results
          run_comparison
        end

        # Expect #wrap_method! to not exceed 5x control baseline
        it { expect(results[:wrap_no_args].utime).to be <= results[:control].utime * 5 }

        # Expect #override_method! to not exceed 3x control baseline
        it { expect(results[:override_no_args].utime).to be <= results[:control].utime * 3 }
      end
    end
  end
end
