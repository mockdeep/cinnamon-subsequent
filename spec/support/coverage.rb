# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  enable_coverage :branch

  add_filter "_spec.rb"
  add_filter "spec/support"

  # The GTK / UI / X11 layer needs a real display and is verified by the smoke
  # test plus visual inspection, not RSpec (see AGENTS.md). It isn't loaded by
  # these specs, but filter it explicitly so the report can't be skewed by it.
  add_filter "lib/app.rb"
  add_filter "lib/sync.rb"
  add_filter "lib/ui"
  add_filter "lib/x11"

  add_group "Lib", "lib"
end
