require 'spec_helper'
require_relative '../spec_helper'
require 'datadog/di/el'

# standard:disable Lint/AssignmentInCondition

class ELTestIvarClass
  def initialize
    @ivar = 42
  end
end

class SubELTestIvarClass < ELTestIvarClass
end

module ELTestMod
  class ELTestIvarClass
  end
end

RSpec.describe Datadog::DI::EL do
  di_test

  let(:compiler) { Datadog::DI::EL::Compiler.new }

  dir = File.join(File.dirname(__FILE__), 'integration_cases')
  (Dir.entries(dir) - %w[. ..]).sort.each do |basename|
    next if File.extname(basename) != '.yml'

    context basename do
      # Do not symbolize names when loading the specs because AST uses string keys
      specs = load_yaml_file(File.join(dir, basename), permitted_classes: %i[
        ELTestIvarClass
        SubELTestIvarClass
        ELTestMod::ELTestIvarClass
      ])
      specs.each do |spec|
        describe name = spec.fetch('name') do
          let(:ast) { spec.fetch('ast') }
          let(:expected) { spec.fetch('compiled') }

          let(:compiled) { compiler.compile(ast) }
          let(:expr) { Datadog::DI::EL::Expression.new('(expression)', compiled) }

          let(:evaluated) do
            expr.evaluate(context)
          end

          let(:context) do
            Datadog::DI::Context.new(locals: locals, target_self: target,
              probe: nil, settings: nil, serializer: nil)
          end

          if error = spec['error']
            let(:expected_compile_error) { error }

            it 'fails to compile' do
              expect do
                compiled
              end.to raise_error do |e|
                expect(e.message).to start_with(expected_compile_error)
              end
            end
          end

          if evals = spec['eval']
            evals.each_with_index do |eval_spec, index|
              context(eval_spec.key?('name') ? "eval: #{eval_spec["name"]}" : "eval #{index + 1}") do
                let(:locals) { eval_spec['locals']&.transform_keys(&:to_sym) }
                let(:target) do
                  Object.new.tap do |object|
                    object.instance_exec do
                      (eval_spec['instance'] || {}).each do |var_name, value|
                        instance_variable_set(var_name, value)
                      end
                    end
                  end
                end

                if eval_spec.key?('result')
                  let(:expected) { eval_spec['result'] }

                  it 'evaluates to expected value' do
                    expect(evaluated).to eq(expected)
                  end

                  it 'evaluates to expected type' do
                    expect(evaluated.class).to be(expected.class)
                  end
                elsif error = eval_spec['error']
                  let(:expected_error) { error }

                  it 'raises an exception' do
                    expect do
                      evaluated
                    end.to raise_error do |e|
                      # TODO assert on exception class also
                      expect(e.message).to start_with(expected_error)
                    end
                  end
                else
                  raise "Missing result or error expectation for test case: #{name}"
                end
              end
            end
          end
        end
      end
    end
  end
end

# standard:enable Lint/AssignmentInCondition
