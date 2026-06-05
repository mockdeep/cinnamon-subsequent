# frozen_string_literal: true

require "tmpdir"

RSpec.describe PidFile do
  # Point the pidfile at a throwaway runtime dir for each example.
  around do |example|
    Dir.mktmpdir do |dir|
      with_env("XDG_RUNTIME_DIR", dir) { example.run }
    end
  end

  # A /proc cmdline: argv joined by NUL bytes, as the kernel exposes it.
  def cmdline(*argv) = argv.join(0.chr)

  describe ".path" do
    it "lives in XDG_RUNTIME_DIR" do
      dir = ENV.fetch("XDG_RUNTIME_DIR")
      expected = File.join(dir, described_class::NAME)

      expect(described_class.path).to eq(expected)
    end

    it "falls back to the config dir when XDG_RUNTIME_DIR is unset" do
      with_env("XDG_RUNTIME_DIR", nil) do
        expected = File.join(Config::DEFAULT_DIR, described_class::NAME)

        expect(described_class.path).to eq(expected)
      end
    end
  end

  describe ".write / .read" do
    it "writes and reads back the current pid" do
      described_class.write

      expect(described_class.read).to eq(Process.pid)
    end

    it "reads nil when the file is absent" do
      expect(described_class.read).to be_nil
    end

    it "reads nil when the file is malformed" do
      File.write(described_class.path, "not-a-pid")

      expect(described_class.read).to be_nil
    end
  end

  describe ".clear" do
    it "removes the file" do
      described_class.write
      described_class.clear

      expect(File.exist?(described_class.path)).to be(false)
    end

    it "is a no-op when the file is absent" do
      expect { described_class.clear }.not_to raise_error
    end
  end

  describe ".alive?" do
    it "is true for a running process" do
      expect(described_class.alive?(Process.pid)).to be(true)
    end

    it "is true for a process we can't signal (EPERM)" do
      expect(described_class.alive?(1)).to be(true)
    end

    it "is false for a reaped pid" do
      pid = Process.spawn("true")
      Process.wait(pid)

      expect(described_class.alive?(pid)).to be(false)
    end
  end

  describe ".ours?" do
    it "is true when an argv element is the launcher" do
      proc_cmdline = cmdline("ruby", "/opt/app/bin/todo-sidebar")
      allow(File).to receive(:binread).and_return(proc_cmdline)

      expect(described_class.ours?(4242)).to be(true)
    end

    it "is false when the launcher is only a substring of one argument" do
      proc_cmdline = cmdline("bash", "-c", "kill bin/todo-sidebar now")
      allow(File).to receive(:binread).and_return(proc_cmdline)

      expect(described_class.ours?(4242)).to be(false)
    end

    it "is false when the process is gone" do
      allow(File).to receive(:binread).and_raise(Errno::ESRCH)

      expect(described_class.ours?(4242)).to be(false)
    end
  end

  describe ".running_pid" do
    it "is nil when there's no pidfile" do
      expect(described_class.running_pid).to be_nil
    end

    it "returns the pid when it's alive and ours" do
      allow(described_class).to receive_messages(
        read: 4242,
        alive?: true,
        ours?: true,
      )

      expect(described_class.running_pid).to eq(4242)
    end

    it "clears a stale pidfile (dead pid) and returns nil" do
      described_class.write
      allow(described_class).to receive_messages(read: 4242, alive?: false)

      expect(described_class.running_pid).to be_nil
      expect(File.exist?(described_class.path)).to be(false)
    end

    it "rejects an alive pid the kernel reused for something else" do
      allow(described_class).to receive_messages(
        read: 4242,
        alive?: true,
        ours?: false,
      )

      expect(described_class.running_pid).to be_nil
    end
  end
end
