# frozen_string_literal: true
module Lib2
  def self.rescue_error
    raise 'lib2 error'
  rescue
    # do nothing
  end
end
