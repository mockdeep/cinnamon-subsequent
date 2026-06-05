# frozen_string_literal: true

require "config"
require "fileutils"

# The sidebar's pidfile: one source of truth for "is an instance running, and
# which one", shared by the app (which records itself on boot) and the :sidebar
# rake tasks (which read it). Lives in $XDG_RUNTIME_DIR (tmpfs, cleared on
# logout), falling back to the config dir when that's unset.
#
# running_pid verifies before trusting the file: the recorded pid must still be
# alive AND its /proc cmdline must still be our launcher, so a stale file from a
# crash (or one whose pid the kernel reused) reads as "not running" and is
# cleared, rather than pointing at the wrong process to signal. That one
# targeted /proc read replaces scanning every pid in /proc.
module PidFile
  NAME = "cinnamon-subsequent.pid"
  LAUNCHER = "bin/todo-sidebar"

  module_function

  # Absolute path to the pidfile.
  def path
    File.join(ENV.fetch("XDG_RUNTIME_DIR", Config::DEFAULT_DIR), NAME)
  end

  # Record the current process as the running instance.
  def write
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    File.write(path, "#{Process.pid}\n")
  end

  # The recorded pid, or nil if the file is absent or malformed.
  def read
    Integer(File.read(path).strip, 10)
  rescue Errno::ENOENT, ArgumentError
    nil
  end

  # Remove the pidfile, tolerating its absence.
  def clear
    File.delete(path)
  rescue Errno::ENOENT
    nil
  end

  # The pid of the running sidebar, or nil. A recorded pid is trusted only when
  # it's both alive and still our launcher; a stale entry is cleared.
  def running_pid
    pid = read
    return if pid.nil?
    return pid if alive?(pid) && ours?(pid)

    clear
    nil
  end

  # Does a process with this pid exist? EPERM means it exists but isn't ours to
  # signal, and ours? then rejects it.
  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  # Is the process at `pid` actually our sidebar? Matches the launcher as a
  # whole argv element (so an unrelated process merely mentioning the path
  # inside a larger argument doesn't count), via a single targeted /proc read.
  def ours?(pid)
    argv = File.binread("/proc/#{pid}/cmdline").split("\0")
    argv.any? { |arg| arg.end_with?(LAUNCHER) }
  rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES
    false
  end
end
