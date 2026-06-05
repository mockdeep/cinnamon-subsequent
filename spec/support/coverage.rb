# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  enable_coverage :branch

  add_filter "_spec.rb"
  add_filter "spec/support"

  add_group "Lib", "lib"
end
