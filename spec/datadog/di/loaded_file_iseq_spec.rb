require "datadog/di/spec_helper"

RSpec.describe 'all_iseqs' do
  before(:all) do
    require 'libdatadog_api.3.3_x86_64-linux'
  end

  let(:iseqs) do
    Datadog::DI.all_iseqs
  end

  let(:file_iseqs) do
    Datadog::DI.file_iseqs
  end

  it 'returns iseqs' do
    expect(iseqs).not_to be_empty

    iseqs.each do |iseq|
      expect(iseq).to be_a(RubyVM::InstructionSequence)
    end
  end

  # We would like to assert that the iseqs we are getting from the VM are
  # complete. Unfortunately only iseqs that correspond to files that defined
  # methods generally exist in the VM - a file that was executed and has
  # no more executable code (for example, it contained only constant
  # definitions) won't have any iseqs remaining after it was loaded.
  # Therefore it's difficult to establish the set of iseqs that we should
  # be expecting here.
  # Since we do have some knowledge about our own library, for now assert
  # that we have a reasonable set of files from dd-trace-rb in the iseqs.
  it 'returns iseqs for all loaded files' do
    datadog_iseqs = file_iseqs.select do |iseq|
      iseq.absolute_path =~ %r,lib/datadog/,
    end
    #pp datadog_iseqs
    p datadog_iseqs.length
    require'byebug';byebug
    expect(datadog_iseqs.length).to be >= $LOADED_FEATURES.length
  end
end
