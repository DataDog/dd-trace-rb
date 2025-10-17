RSpec.shared_examples_for 'with on_error setting' do
  context 'default without settings' do
    subject { described_class.new }

    it { expect(subject.on_error).to be_nil }
  end

  context 'when given a Proc' do
    subject { described_class.new(on_error: proc {}) }

    it { expect(subject.on_error).to be_a(Proc) }
  end

  context 'when given a object of wrong type' do
    subject { described_class.new(on_error: 1) }

    it { expect { subject }.to raise_error(ArgumentError) }
  end
end

RSpec.shared_examples_for 'with error_status_codes setting' do |env:, default:, settings_class:, option:|
  let(:result) { subject.send(option) }

  context 'default without settings' do
    subject { settings_class.new }

    it { expect(result).not_to include(default.min - 1) }
    it { expect(result).to include(default.min) }
    it { expect(result).to include(default.max) }
    it { expect(result).not_to include(default.max + 1) }
  end

  context 'when given error_status_codes' do
    subject { settings_class.new(option_hash) }
    let(:option_hash) { { option => option_value } }

    context 'when given a single value' do
      let(:option_value) { 500 }

      it { expect(result).not_to include 400 }
      it { expect(result).not_to include 499 }
      it { expect(result).to include 500 }
      it { expect(result).not_to include 599 }
      it { expect(result).not_to include 600 }
    end

    context 'when given an array of integers' do
      let(:option_value) { [400, 500] }

      it { expect(result).to include 400 }
      it { expect(result).not_to include 499 }
      it { expect(result).to include 500 }
      it { expect(result).not_to include 599 }
      it { expect(result).not_to include 600 }
    end

    context 'when given a range' do
      let(:option_value) { 500..600 }

      it { expect(result).not_to include 400 }
      it { expect(result).not_to include 499 }
      it { expect(result).to include 500 }
      it { expect(result).to include 599 }
      it { expect(result).to include 600 }
    end

    context 'when given an array of integer and range' do
      let(:option_value) { [400, 500..600] }

      it { expect(result).to include 400 }
      it { expect(result).not_to include 499 }
      it { expect(result).to include 500 }
      it { expect(result).to include 599 }
      it { expect(result).to include 600 }
    end
  end

  context 'when configured with environment variable' do
    subject { settings_class.new }

    context 'when given a single value' do
      around do |example|
        ClimateControl.modify(env => '500') do
          example.run
        end
      end

      it { expect(result).not_to include 400 }
      it { expect(result).not_to include 499 }
      it { expect(result).to include 500 }
      it { expect(result).not_to include 599 }
      it { expect(result).not_to include 600 }
    end

    context 'when given a comma separated list' do
      around do |example|
        ClimateControl.modify(env => '400,500') do
          example.run
        end
      end

      it { expect(result).to include 400 }
      it { expect(result).not_to include 499 }
      it { expect(result).to include 500 }
      it { expect(result).not_to include 599 }
      it { expect(result).not_to include 600 }
    end

    context 'when given a comma separated list with space' do
      around do |example|
        ClimateControl.modify(env => '400,,500') do
          example.run
        end
      end

      it { expect(result).to include 400 }
      it { expect(result).not_to include 499 }
      it { expect(result).to include 500 }
      it { expect(result).not_to include 599 }
      it { expect(result).not_to include 600 }
    end

    context 'when given a comma separated list with range' do
      around do |example|
        ClimateControl.modify(env => '400,500-600') do
          example.run
        end
      end

      it { expect(result).to include 400 }
      it { expect(result).not_to include 499 }
      it { expect(result).to include 500 }
      it { expect(result).to include 599 }
      it { expect(result).to include 600 }
    end
  end
end
