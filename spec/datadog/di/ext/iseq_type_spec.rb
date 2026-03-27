require "datadog/di/spec_helper"

RSpec.describe 'iseq_type' do
  def iseq_type(iseq)
    Datadog::DI.iseq_type(iseq)
  end

  before(:all) do
    skip 'iseq_type requires rb_iseq_type (not available on this Ruby)' unless Datadog::DI.respond_to?(:iseq_type)
  end

  it 'returns :top for a compiled file' do
    iseq = RubyVM::InstructionSequence.compile_file(__FILE__)
    expect(iseq_type(iseq)).to eq(:top)
  end

  it 'returns :top for eval with top-level code' do
    iseq = RubyVM::InstructionSequence.compile('1 + 1')
    expect(iseq_type(iseq)).to eq(:top)
  end

  it 'returns :method for method iseqs from all_iseqs' do
    method_iseqs = Datadog::DI.all_iseqs.select do |iseq|
      iseq.absolute_path && iseq_type(iseq) == :method
    end
    expect(method_iseqs).not_to be_empty
  end

  it 'returns :top for whole-file iseqs from all_iseqs' do
    top_iseqs = Datadog::DI.all_iseqs.select do |iseq|
      iseq.absolute_path && iseq_type(iseq) == :top
    end
    expect(top_iseqs).not_to be_empty
  end
end
