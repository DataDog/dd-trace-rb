require 'minitest'
require 'minitest/autorun'
require 'ddtrace'
require 'active_record'
require 'elasticsearch/transport'
require 'redis'
require 'faraday'
require 'aws-sdk'
require 'sucker_punch'
require 'dalli'
require 'resque'

class MonkeyTest < Minitest::Test
  def test_autopatch_modules
    expected = {
      rails: true,
      elasticsearch: true,
      http: true,
      redis: true,
      grape: true,
      faraday: true,
      aws: true,
      sucker_punch: true,
      mongo: true,
      dalli: true,
      resque: true,
      active_record: false,
      racecar: false
    }

    assert_equal(expected, Datadog::Monkey.autopatch_modules)
  end

  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/LineLength
  # rubocop:disable Metrics/MethodLength
  def test_patch_module
    # because of this test, this should be a separate rake task,
    # else the module could have been already imported in some other test
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Grape::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Aws::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ rails: false, elasticsearch: false, http: false, redis: false, grape: false, faraday: false, aws: false, sucker_punch: false, active_record: false, mongo: false, dalli: false, resque: false, racecar: false }, Datadog::Monkey.get_patched_modules())

    Datadog::Monkey.patch_module(:redis)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Grape::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Aws::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    refute(Datadog::Contrib::Faraday::Patcher.patched?)
    assert_equal({ rails: false, elasticsearch: false, http: false, redis: true, grape: false, faraday: false, aws: false, sucker_punch: false, active_record: false, mongo: false, dalli: false, resque: false, racecar: false }, Datadog::Monkey.get_patched_modules())

    # now do it again to check it's idempotent
    Datadog::Monkey.patch_module(:redis)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Grape::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Aws::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    refute(Datadog::Contrib::Faraday::Patcher.patched?)
    assert_equal({ rails: false, elasticsearch: false, http: false, redis: true, grape: false, faraday: false, aws: false, sucker_punch: false, active_record: false, mongo: false, dalli: false, resque: false, racecar: false }, Datadog::Monkey.get_patched_modules())

    Datadog::Monkey.patch(elasticsearch: true, redis: true)
    assert_equal(true, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Grape::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Aws::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ rails: false, elasticsearch: true, http: false, redis: true, grape: false, faraday: false, aws: false, sucker_punch: false, active_record: false, mongo: false, dalli: false, resque: false, racecar: false }, Datadog::Monkey.get_patched_modules())

    # verify that active_record is not auto patched by default
    Datadog::Monkey.patch_all()
    assert_equal(true, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Grape::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Aws::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ rails: false, elasticsearch: true, http: true, redis: true, grape: false, faraday: true, aws: true, sucker_punch: true, active_record: false, mongo: false, dalli: true, resque: true, racecar: false }, Datadog::Monkey.get_patched_modules())

    Datadog::Monkey.patch_module(:active_record)
    assert_equal(true, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Grape::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Aws::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ rails: false, elasticsearch: true, http: true, redis: true, grape: false, faraday: true, aws: true, sucker_punch: true, active_record: true, mongo: false, dalli: true, resque: true, racecar: false }, Datadog::Monkey.get_patched_modules())
  end
end
