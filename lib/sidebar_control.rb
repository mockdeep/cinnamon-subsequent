# frozen_string_literal: true

require "config"
require "pid_file"
require "rbconfig"

# Start/stop/restart the detached sidebar process. The single way the sidebar
# is launched: both the :sidebar rake tasks and the login autostart entry go
# through here (via bin/sidebarctl), so an instance started at login gets the
# same log and environment as one started by hand — previously autostart ran
# bin/todo-sidebar directly and a crash left no record at all.
#
# Finds the running instance via the pidfile the app records on boot (PidFile),
# so locating it is a verified read of one pid, not a scan of the process table.
module SidebarControl
  BIN = File.expand_path("../bin/todo-sidebar", __dir__)
  LOG = "/tmp/todo-sidebar.log"

  # Rotate at ~1MB, keeping one generation. Restarts append forever otherwise
  # and nothing else rotates this; a Ruby crash dump alone runs to thousands of
  # lines, so the cap is what keeps the previous one still findable.
  LOG_MAX_BYTES = 1_000_000

  # glibc's allocator checks, enabled by the `debug.malloc_check` config key.
  # The LD_PRELOAD is not optional: as of glibc 2.34 the malloc_check machinery
  # lives in libc_malloc_debug.so rather than libc proper, so setting the
  # tunable alone is silently ignored. check=3 reports and aborts on the first
  # damaged chunk, which catches a heap overwrite at the next allocator
  # operation touching it rather than thousands of allocations later.
  #
  # MALLOC_PERTURB_ stayed in libc and needs no preload — it fills freed memory
  # with a non-zero byte so a use-after-free reads obvious garbage instead of
  # plausible stale data.
  MALLOC_DEBUG_ENV = {
    "LD_PRELOAD" => "libc_malloc_debug.so.0",
    "GLIBC_TUNABLES" => "glibc.malloc.check=3",
    "MALLOC_PERTURB_" => "165",
  }.freeze

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

  # Stop then start, defined here rather than as a pair of rake prerequisites
  # so the rake task and bin/sidebarctl share one definition.
  def restart
    stop
    start
  end

  # Print the running pid, or that nothing is running.
  def status
    pid = PidFile.running_pid
    puts pid.nil? ? "sidebar not running" : "sidebar running (pid #{pid})"
  end

  # Spawn in a new session (setsid) so it outlives the caller — the rake task,
  # or cinnamon-session's autostart slot. Output is logged since the process is
  # detached from any terminal. DISPLAY is defaulted for a non-graphical
  # invocation. The spawned app records its own pid.
  def spawn_detached
    ENV["DISPLAY"] = ENV.fetch("DISPLAY", ":0")
    env = child_env
    prepare_log(env)
    Process.spawn(
      env,
      "setsid",
      RbConfig.ruby,
      BIN,
      in: File::NULL,
      out: [LOG, "a"],
      err: [:child, :out],
    )
  end

  # Extra environment for the child. Empty in normal use — the malloc debugging
  # vars are added only when config.json asks for them.
  def child_env
    Config.load.malloc_check? ? MALLOC_DEBUG_ENV.dup : {}
  end

  # Rotate, then stamp the log with a dated line naming what we're launching.
  # Without it the log is undated, and a detached process leaves no other record
  # of when a run began — which is what made the last crash impossible to place.
  def prepare_log(env)
    rotate_log
    banner(env)
  end

  # Move the log aside once it passes the cap, keeping one generation.
  # File.size? is nil for both a missing and an empty log, which is exactly the
  # "nothing to rotate" case.
  def rotate_log(path = LOG)
    size = File.size?(path)
    return if size.nil? || size <= LOG_MAX_BYTES

    File.rename(path, "#{path}.1")
  rescue Errno::ENOENT
    nil
  end

  # Append the dated marker for one launch, noting whether the allocator checks
  # are on so a later crash in this log can be read in the right context.
  def banner(env, path = LOG)
    mode = env.empty? ? "" : " [malloc-check]"
    stamp = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")
    File.open(path, "a") do |log|
      log.puts("--- sidebar starting #{stamp}#{mode} ---")
    end
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
