# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  enable_coverage :branch

  add_filter "_spec.rb"
  add_filter "spec/support"

  # The GTK widget / Xlib layer needs a real display and meaningful assertions
  # against rendered output, so it's verified by the smoke test plus visual
  # inspection, not RSpec (see AGENTS.md). app.rb and sync.rb ARE covered (the
  # orchestration logic, with the widgets stubbed), so they're not filtered.
  add_filter "lib/ui"
  add_filter "lib/x11"

  add_group "Lib", "lib"
end
