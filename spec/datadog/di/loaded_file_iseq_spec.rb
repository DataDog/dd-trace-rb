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
  it 'returns iseqs for loaded files' do
    datadog_iseqs = file_iseqs.select do |iseq|
      iseq.absolute_path =~ %r,lib/datadog/,
    end
    paths = datadog_iseqs.map(&:absolute_path).uniq

    # When this test was written, there were 650+ files with
    # iseqs in them and 5200+ iseq objects available.
    # Allow for a margin but assume the amount of code in dd-trace-rb
    # will generally grow over time.
    expect(paths.length).to be > 500
    expect(datadog_iseqs.length).to be > 4000

    # An initial attempt at this test compared the number of iseqs
    # we got to the size of $LOADED_FEATURES. This is not a working
    # comparison because loaded features contain Ruby files with constants
    # only (simplest case) that have no iseqs, therefore generally,
    # the loaded features and available iseqs are not correlated.
  end
end
