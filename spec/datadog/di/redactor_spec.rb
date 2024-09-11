require "datadog/di/redactor"

class DIRedactorSpecSensitiveType; end

class DIRedactorSpecWildCard; end

class DIRedactorSpecWildCardClass; end

class DIRedactorSpecWildCa; end

class DIRedactorSpecPrefixWildCard; end

class DIRedactorSpecDoubleColon; end

module DIRedactorSpec
  class SensitiveType; end

  class NotSensitiveType; end

  class WildCardSensitiveType; end

  class ExactMatch; end

  class DoubleColonNested; end

  class DoubleColonWildCardType; end
end

RSpec.describe Datadog::DI::Redactor do
  let(:settings) do
    double("settings").tap do |settings|
      allow(settings).to receive(:dynamic_instrumentation).and_return(di_settings)
    end
  end

  let(:di_settings) do
    double("di settings").tap do |settings|
      allow(settings).to receive(:enabled).and_return(true)
      allow(settings).to receive(:propagate_all_exceptions).and_return(false)
      allow(settings).to receive(:redacted_identifiers).and_return([])
    end
  end

  let(:redactor) do
    Datadog::DI::Redactor.new(settings)
  end

  describe "#redact_identifier?" do
    def self.define_cases(cases)
      cases.each do |(label, identifier_, redact_)|
        identifier, redact = identifier_, redact_

        context label do
          let(:identifier) { identifier }

          it do
            expect(redactor.redact_identifier?(identifier)).to be redact
          end
        end
      end
    end

    cases = [
      ["lowercase", "password", true],
      ["uppercase", "PASSWORD", true],
      ["with removed punctiation", "pass_word", true],
      ["with non-removed punctuation", "pass/word", false],
    ]

    define_cases(cases)

    context "when user-defined redacted identifiers exist" do
      before do
        expect(di_settings).to receive(:redacted_identifiers).and_return(%w[foo пароль Ключ @var])
      end

      cases = [
        ["exact user-defined identifier", "foo", true],
        ["prefix of user-defined identifier", "f", false],
        ["suffix of user-defined identifier", "oo", false],
        ["user-defined identifier with extra removeable punctuation", "f-o-o", true],
        ["user-defined identifier with extra non-removeable punctuation", "f.o.o", false],
        ["user-defined identifier is not ascii, target identifier is in another case", "ПАРОЛь", true],
        ["user-defined identifier is not ascii and uses mixed case in definition", "ключ", true],
        ["user-defined identifier is not ascii and uses mixed case in definition and is not exact match", "ключ1", false],
        ["@ in definition", "var", true],
        ["@ in definition but name does not match", "var1", false],
        ["@ in target identifier", "@foo", true],
        ["@ in target identifier but name does not match", "@foo1", false],
      ]

      define_cases(cases)
    end
  end

  describe "#redact_type?" do
    let(:redacted_type_names) {
      %w[
        DIRedactorSpecSensitiveType
        DIRedactorSpecWildCard*
        DIRedactorSpec::ExactMatch
        DIRedactorSpec::WildCard*
        SensitiveType
        SensitiveType*
        ::DIRedactorSpecDoubleColon
        ::DIRedactorSpec::DoubleColonNested
        ::DIRedactorSpec::DoubleColonWildCard*
      ]
    }

    def self.define_cases(cases)
      cases.each do |(label, value_, redact_)|
        value, redact = value_, redact_

        context label do
          let(:value) { value }

          it do
            expect(redactor.redact_type?(value)).to be redact
          end
        end
      end
    end

    context "redacted type list is checked" do
      before do
        expect(di_settings).to receive(:redacted_type_names).and_return(redacted_type_names)
      end

      cases = [
        ["redacted", DIRedactorSpecSensitiveType.new, true],
        ["not redacted", /123/, false],
        ["primitive type", nil, false],
        ["wild card type whose name is the same as prefix", DIRedactorSpecWildCard.new, true],
        ["wild card type", DIRedactorSpecWildCardClass.new, true],
        ["wild card does not match from beginning", DIRedactorSpecPrefixWildCard.new, false],
        ["partial wild card prefix match", DIRedactorSpecWildCa.new, false],
        ["class object", String, false],
        ["anonymous class object", Class.new, false],
        ["namespaced class - exact match", DIRedactorSpec::ExactMatch.new, true],
        ["namespaced class - wildcard - matched", DIRedactorSpec::WildCardSensitiveType.new, true],
        ["namespaced class - tail component match only", DIRedactorSpec::SensitiveType.new, false],
        ["double-colon top-level specification", DIRedactorSpecDoubleColon.new, true],
        ["double-colon nested specification", DIRedactorSpec::DoubleColonNested.new, true],
        ["double-colon nested wildcard", DIRedactorSpec::DoubleColonWildCardType.new, true],
      ]

      define_cases(cases)
    end

    context "redacted type list is not checked" do
      before do
        expect(di_settings).not_to receive(:redacted_type_names)
      end

      cases = [
        ["instance of anonymous class", Class.new.new, false],
      ]

      define_cases(cases)
    end
  end
end
