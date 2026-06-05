# frozen_string_literal: true

require_relative "support/coverage"

# The lib files require each other by bare name (e.g. `require "config"`),
# relying on lib/ being on the load path — bin/todo-sidebar does this too.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "config"
require "trello_client"
require "board_fetch"
require "pid_file"
require "sidebar_control"
require "sync"
# NOTE: lib/app.rb (and the ui/* widgets it pulls in) is required by app_spec,
# not here — loading a Gtk widget class calls Gtk.init, so it needs a display.

require_relative "support/env"
require_relative "support/factories"
require_relative "support/trello"
require_relative "support/webmock"

RSpec.configure do |config|
  config.order = :random

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.filter_run(focus: true)
  config.run_all_when_everything_filtered = true

  config.expect_with(:rspec) do |c|
    c.syntax = :expect
  end
end
