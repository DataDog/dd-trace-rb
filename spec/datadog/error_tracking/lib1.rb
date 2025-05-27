# frozen_string_literal: true
module Lib1
  def self.rescue_error
    raise 'lib1 error'
  rescue
    # do nothing
  end
end
