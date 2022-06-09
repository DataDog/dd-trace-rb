require 'spec_helper'

RSpec.shared_examples 'an optional string argument' do |argument|
  context 'when it is nil' do
    let(argument.to_sym) { nil }
    it { is_expected.to be_a_kind_of(described_class) }
  end

  context 'when it is empty string' do
    let(argument.to_sym) { '' }
    it { expect { subject }.to raise_error(ArgumentError) }
  end

  context 'when it is valid' do
    let(argument.to_sym) { 'valid string' }
    it { is_expected.to be_a_kind_of(described_class) }
  end
end

RSpec.shared_examples 'a string argument' do |argument|
  context 'when it is nil' do
    let(argument.to_sym) { nil }
    it { expect { subject }.to raise_error(ArgumentError) }
  end

  context 'when it is empty string' do
    let(argument.to_sym) { '' }
    it { expect { subject }.to raise_error(ArgumentError) }
  end

  context 'when it is integer' do
    let(argument.to_sym) { 1.0 }
    it { expect { subject }.to raise_error(ArgumentError) }
  end

  context 'when it is valid' do
    let(argument.to_sym) { 'valid string' }
    it { is_expected.to be_a_kind_of(described_class) }
  end
end

RSpec.shared_examples 'a boolean argument' do |argument|
  context 'when it is nil' do
    let(argument.to_sym) { nil }
    it { expect { subject }.to raise_error(ArgumentError) }
  end

  context 'when it is integer' do
    let(argument.to_sym) { 1 }
    it { expect { subject }.to raise_error(ArgumentError) }
  end

  context 'when it is true' do
    let(argument.to_sym) { true }
    it { is_expected.to be_a_kind_of(described_class) }
  end

  context 'when it is false' do
    let(argument.to_sym) { false }
    it { is_expected.to be_a_kind_of(described_class) }
  end
end

RSpec.shared_examples 'an optional boolean argument' do |argument|
  context 'when it is nil' do
    let(argument.to_sym) { nil }
    it { is_expected.to be_a_kind_of(described_class) }
  end

  context 'when it is integer' do
    let(argument.to_sym) { 1 }
    it { expect { subject }.to raise_error(ArgumentError) }
  end

  context 'when it is true' do
    let(argument.to_sym) { true }
    it { is_expected.to be_a_kind_of(described_class) }
  end

  context 'when it is false' do
    let(argument.to_sym) { false }
    it { is_expected.to be_a_kind_of(described_class) }
  end
end
