require 'spec_helper'

require 'datadog/profiling/backtrace_location'

RSpec.describe Datadog::Profiling::BacktraceLocation do
  subject(:backtrace_location) { new_backtrace_location(base_label, lineno, path) }

  def new_backtrace_location(
    base_label = 'to_s',
    lineno = 15,
    path = 'path/to/file.rb'
  )
    described_class.new(
      base_label,
      lineno,
      path
    )
  end

  let(:base_label) { double('base_label') }
  let(:lineno) { double('lineno') }
  let(:path) { double('path') }

  it do
    is_expected.to have_attributes(
      base_label: base_label,
      lineno: lineno,
      path: path
    )
  end

  shared_context 'equivalent BacktraceLocations' do
    let(:backtrace_location_one) { new_backtrace_location }
    let(:backtrace_location_two) { new_backtrace_location }
  end

  describe '#==' do
    context 'for two BacktraceLocations with same content' do
      include_context 'equivalent BacktraceLocations'
      it { expect(backtrace_location_one == backtrace_location_two).to be true }
    end
  end

  describe '#eql?' do
    context 'for two BacktraceLocations with same content' do
      include_context 'equivalent BacktraceLocations'
      it { expect(backtrace_location_one.eql?(backtrace_location_two)).to be true }
    end
  end

  describe '#hash' do
    context 'for two BacktraceLocations with same content' do
      include_context 'equivalent BacktraceLocations'
      it { expect(backtrace_location_one.hash).to be_a_kind_of(Integer) }
      it { expect(backtrace_location_one.hash).to eq(backtrace_location_two.hash) }
    end
  end
end
