require 'spec_helper'

require 'benchmark'
require 'ddtrace/shim'

RSpec.describe Datadog::Shim do
  let(:iterations) { 1_000_000 }

  describe Datadog::Shim::Double do
    let(:test_class) do
      Class.new do
        def foo
          :foo
        end
      end
    end
    let(:object) { test_class.new }

    shared_context 'Double#wrap_method! with block' do
      let(:wrap_method_with_block_double) do
        Datadog::Shim.double(object) do |shim|
          shim.wrap_method!(:foo) do |*args, &block|
            shim.shim_target.foo(*args, &block)
          end
        end
      end
    end

    shared_context 'Double#wrap_method! without args' do
      let(:wrap_method_without_args_double) do
        Datadog::Shim.double(object) do |shim|
          shim.wrap_method!(:foo) do
            shim.shim_target.foo
          end
        end
      end
    end

    shared_context 'Double#inject_method! with block' do
      let(:inject_method_with_block_double) do
        Datadog::Shim.double(object) do |shim|
          shim.inject_method!(:foo) do |*args, &block|
            shim.shim_target.foo(*args, &block)
          end
        end
      end
    end

    shared_context 'Double#inject_method! without args' do
      let(:inject_method_without_args_double) do
        Datadog::Shim.double(object) do |shim|
          shim.inject_method!(:foo) do
            shim.shim_target.foo
          end
        end
      end
    end

    describe 'benchmark' do
      include_context 'Double#wrap_method! with block'
      include_context 'Double#wrap_method! without args'
      include_context 'Double#inject_method! with block'
      include_context 'Double#inject_method! without args'

      describe 'baseline comparison' do
        it do
          Benchmark.bm do |x|
            x.report('control') do
              iterations.times { raise RuntimeError.new if object.foo != :foo }
            end

            x.report('Double#wrap_method! with block') do
              iterations.times { raise RuntimeError.new if wrap_method_with_block_double.foo != :foo }
            end

            x.report('Double#wrap_method! without args') do
              iterations.times { raise RuntimeError.new if wrap_method_without_args_double.foo != :foo }
            end

            x.report('Double#inject_method! with block') do
              iterations.times { raise RuntimeError.new if inject_method_with_block_double.foo != :foo }
            end

            x.report('Double#inject_method! without args') do
              iterations.times { raise RuntimeError.new if inject_method_without_args_double.foo != :foo }
            end
          end
        end
      end
    end
  end
end