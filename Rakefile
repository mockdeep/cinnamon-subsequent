# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
require "sidebar_control"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: [:spec, :rubocop]

namespace :sidebar do
  desc "Launch the sidebar (detached) unless it's already running"
  task(:start) { SidebarControl.start }

  desc "Stop the running sidebar"
  task(:stop) { SidebarControl.stop }

  desc "Restart the sidebar"
  task restart: [:stop, :start]

  desc "Report whether the sidebar is running"
  task(:status) { SidebarControl.status }
end
