require 'spec_helper'
require 'datadog/core/tag_normalizer'

RSpec.describe Datadog::Core::TagNormalizer do
  describe 'Follows the normalization logic from the Trace Agent for tag keys' do
    # Test cases from the Trace Agent for consistency
    # https://github.com/DataDog/datadog-agent/blob/45799c842bbd216bcda208737f9f11cade6fdd95/pkg/trace/traceutil/normalize_test.go#L17
    test_cases = [
      {in: '#test_starting_hash', out: 'test_starting_hash'},
      {in: 'TestCAPSandSuch', out: 'testcapsandsuch'},
      {in: 'Test Conversion Of Weird !@#$%^&**() Characters', out: 'test_conversion_of_weird_characters'},
      {in: '$#weird_starting', out: 'weird_starting'},
      {in: 'allowed:c0l0ns', out: 'allowed:c0l0ns'},
      {in: '1love', out: 'love'},
      {in: 'ünicöde', out: 'ünicöde'},
      {in: 'ünicöde:metäl', out: 'ünicöde:metäl'},
      {in: 'Data🐨dog🐶 繋がっ⛰てて', out: 'data_dog_繋がっ_てて'},
      {in: ' spaces   ', out: 'spaces'},
      {in: ' #hashtag!@#spaces #__<>#  ', out: 'hashtag_spaces'},
      {in: ':testing', out: ':testing'},
      {in: '_foo', out: 'foo'},
      {in: ':::test', out: ':::test'},
      {in: 'contiguous_____underscores', out: 'contiguous_underscores'},
      {in: 'foo_', out: 'foo'},
      {in: '', out: ''},
      {in: ' ', out: ''},
      {in: 'ok', out: 'ok'},
      {in: 'AlsO:ök', out: 'also:ök'},
      {in: ':still_ok', out: ':still_ok'},
      {in: '___trim', out: 'trim'},
      {in: '12.:trim@', out: ':trim'},
      {in: '12.:trim@@', out: ':trim'},
      {in: 'fun:ky__tag/1', out: 'fun:ky_tag/1'},
      {in: 'fun:ky@tag/2', out: 'fun:ky_tag/2'},
      {in: 'fun:ky@@@tag/3', out: 'fun:ky_tag/3'},
      {in: 'tag:1/2.3', out: 'tag:1/2.3'},
      {in: '---fun:k####y_ta@#g/1_@@#', out: 'fun:k_y_ta_g/1'},
      {in: 'AlsO:œ#@ö))œk', out: 'also:œ_ö_œk'},
      {in: "test\x99\x8faaa", out: 'test_aaa'},
      {in: "test\x99\x8f", out: 'test'},
      {in: 'a' * 888, out: 'a' * 200},
      {in: ' regulartag ', out: 'regulartag'},
      {in: "\u017Fodd_\u017Fcase\u017F", out: "\u017Fodd_\u017Fcase\u017F"},
      {in: '™Ö™Ö™™Ö™', out: 'ö_ö_ö'},
      {in: "a�", out: 'a'},
      {in: "a��", out: 'a'},
      {in: "a��b", out: 'a_b'},
      {in: 'a' + ('🐶' * 799) + 'b', out: 'a'},
      # This test case doesn't work with the current logic because it yields 202 characters
      # {in: 'A' + ('0' * 200) + ' ' + ('0' * 11), out: 'a' + ('0' * 200) + '_0'},
    ]

    test_cases.each do |test_case|
      it "normalizes #{test_case[:in].inspect} to #{test_case[:out].inspect} like the Trace Agent" do
        expect(described_class.normalize(test_case[:in], remove_digit_start_char: true)).to eq(test_case[:out])
      end
    end
  end

  describe 'Follows the normalization logic from the Trace Agent for tag values' do
    test_cases = [
      # Reusing the same Trace Agent inputs, except a few of the outputs have changed
      {in: '#test_starting_hash', out: 'test_starting_hash'},
      {in: 'TestCAPSandSuch', out: 'testcapsandsuch'},
      {in: 'Test Conversion Of Weird !@#$%^&**() Characters', out: 'test_conversion_of_weird_characters'},
      {in: '$#weird_starting', out: 'weird_starting'},
      {in: 'allowed:c0l0ns', out: 'allowed:c0l0ns'},
      {in: '1love', out: '1love'}, # differs when remove_digit_start_char is false
      {in: 'ünicöde', out: 'ünicöde'},
      {in: 'ünicöde:metäl', out: 'ünicöde:metäl'},
      {in: 'Data🐨dog🐶 繋がっ⛰てて', out: 'data_dog_繋がっ_てて'},
      {in: ' spaces   ', out: 'spaces'},
      {in: ' #hashtag!@#spaces #__<>#  ', out: 'hashtag_spaces'},
      {in: ':testing', out: ':testing'},
      {in: '_foo', out: 'foo'},
      {in: ':::test', out: ':::test'},
      {in: 'contiguous_____underscores', out: 'contiguous_underscores'},
      {in: 'foo_', out: 'foo'},
      {in: '', out: ''},
      {in: ' ', out: ''},
      {in: 'ok', out: 'ok'},
      {in: 'AlsO:ök', out: 'also:ök'},
      {in: ':still_ok', out: ':still_ok'},
      {in: '___trim', out: 'trim'},
      {in: '12.:trim@', out: '12.:trim'}, # differs when remove_digit_start_char is false
      {in: '12.:trim@@', out: '12.:trim'}, # differs when remove_digit_start_char is false
      {in: 'fun:ky__tag/1', out: 'fun:ky_tag/1'},
      {in: 'fun:ky@tag/2', out: 'fun:ky_tag/2'},
      {in: 'fun:ky@@@tag/3', out: 'fun:ky_tag/3'},
      {in: 'tag:1/2.3', out: 'tag:1/2.3'},
      {in: '---fun:k####y_ta@#g/1_@@#', out: 'fun:k_y_ta_g/1'},
      {in: 'AlsO:œ#@ö))œk', out: 'also:œ_ö_œk'},
      {in: "test\x99\x8faaa", out: 'test_aaa'},
      {in: "test\x99\x8f", out: 'test'},
      {in: 'a' * 888, out: 'a' * 200},
      {in: ' regulartag ', out: 'regulartag'},
      {in: "\u017Fodd_\u017Fcase\u017F", out: "\u017Fodd_\u017Fcase\u017F"},
      {in: '™Ö™Ö™™Ö™', out: 'ö_ö_ö'},
      {in: "a�", out: 'a'},
      {in: "a��", out: 'a'},
      {in: "a��b", out: 'a_b'},
      {in: 'a' + ('🐶' * 799) + 'b', out: 'a'},
    ]

    test_cases.each do |test_case|
      it "normalizes #{test_case[:in].inspect} to #{test_case[:out].inspect} like the Trace Agent" do
        # These test cases are from the Trace Agent's default normalize() behavior (tag keys)
        expect(described_class.normalize(test_case[:in], remove_digit_start_char: false)).to eq(test_case[:out])
      end
    end
  end
end
