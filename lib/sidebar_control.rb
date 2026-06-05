# frozen_string_literal: true

require "pid_file"
require "rbconfig"

# Start/stop/restart the detached sidebar process for the :sidebar rake tasks.
# Finds the running instance via the pidfile the app records on boot (PidFile),
# so locating it is a verified read of one pid, not a scan of the process table.
module SidebarControl
  BIN = File.expand_path("../bin/todo-sidebar", __dir__)
  LOG = "/tmp/todo-sidebar.log"

  module_function

  # Launch the sidebar detached unless one is already running.
  def start
    running = PidFile.running_pid
    return puts("sidebar already running (pid #{running})") if running

    Process.detach(spawn_detached)
    wait_for { PidFile.running_pid }
    report_start(PidFile.running_pid)
  end

  # TERM the instance, then KILL it if it ignores that.
  def stop
    pid = PidFile.running_pid
    return puts("sidebar not running") if pid.nil?

    signal(pid, "TERM")
    wait_for { PidFile.running_pid.nil? }
    leftover = PidFile.running_pid
    signal(leftover, "KILL") if leftover
    PidFile.clear
    puts "sidebar stopped (pid #{pid})"
  end

  # Print the running pid, or that nothing is running.
  def status
    pid = PidFile.running_pid
    puts pid.nil? ? "sidebar not running" : "sidebar running (pid #{pid})"
  end

  # Spawn in a new session (setsid) so it outlives the rake process; output is
  # logged since the process is detached from the terminal. DISPLAY is defaulted
  # for a non-graphical rake invocation. The spawned app records its own pid.
  def spawn_detached
    ENV["DISPLAY"] = ENV.fetch("DISPLAY", ":0")
    Process.spawn(
      "setsid",
      RbConfig.ruby,
      BIN,
      in: File::NULL,
      out: [LOG, "a"],
      err: [:child, :out],
    )
  end

  # Report the outcome of a start attempt from the pid found afterwards.
  def report_start(pid)
    if pid.nil?
      puts "sidebar failed to start - see #{LOG}"
    else
      puts "sidebar started (pid #{pid})"
    end
  end

  # Send `name` to `pid`, ignoring it if already exited.
  def signal(pid, name)
    Process.kill(name, pid)
  rescue Errno::ESRCH
    nil
  end

  # Poll the block up to ~4s, returning as soon as it's truthy.
  def wait_for
    20.times do
      return if yield

      sleep(0.2)
    end
  end
end
