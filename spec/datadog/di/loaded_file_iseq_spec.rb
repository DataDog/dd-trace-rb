require "datadog/di/spec_helper"

RSpec.describe 'all_iseqs' do
  before(:all) do
    require 'libdatadog_api.3.3_x86_64-linux'
  end

  let(:iseqs) do
    Datadog::DI::VMAccess.all_iseqs
  end

  let(:file_iseqs) do
    iseqs.select do |iseq|
      iseq.first_lineno == 0
    end
  end

  it 'returns iseqs' do
    expect(iseqs).not_to be_empty

    iseqs.each do |iseq|
      expect(iseq).to be_a(RubyVM::InstructionSequence)
    end
  end

  it 'returns iseqs for all required files' do
    iseq_paths = iseqs.map(&:path)
    #pp $LOADED_FEATURES - iseq_paths
    require'byebug';byebug
    expect(file_iseqs.length).to be >= $LOADED_FEATURES.length
  end
end
