module ObjectHelpers
  RSpec::Matchers.define :be_a_frozen_copy_of do |expected|
    match do |actual|
      expect(actual).to eq expected
      expect(actual).to_not be expected
      expect(actual.frozen?).to be true
    end
  end

  RSpec::Matchers.define :be_a_copy_of do |expected|
    match do |actual|
      expect(actual).to eq expected
      expect(actual).to_not be expected
    end
  end
end
