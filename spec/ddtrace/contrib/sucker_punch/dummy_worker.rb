require 'sucker_punch'

class DummyWorker
  include ::SuckerPunch::Job

  def perform(action = :none)
    1 / 0 if action == :fail
  end
end
