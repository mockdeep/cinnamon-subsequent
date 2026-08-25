# frozen_string_literal: true

require "tmpdir"

RSpec.describe SidebarControl do
  # A scratch log per example. The banner/rotate helpers take a path precisely
  # so these never touch the real /tmp/todo-sidebar.log.
  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  def log_path = File.join(@dir, "todo-sidebar.log")

  def stub_config(malloc_check:)
    allow(Config).to receive(:load)
      .and_return(instance_double(Config, malloc_check?: malloc_check))
  end

  describe ".start" do
    it "reports the existing pid without spawning when one is running" do
      allow(PidFile).to receive(:running_pid).and_return(4242)
      allow(described_class).to receive(:spawn_detached)

      expect { described_class.start }
        .to output("sidebar already running (pid 4242)\n").to_stdout
      expect(described_class).not_to have_received(:spawn_detached)
    end

    it "spawns detached and reports the new pid once it registers" do
      allow(PidFile).to receive(:running_pid).and_return(nil, 100)
      allow(described_class).to receive(:spawn_detached).and_return(100)
      allow(Process).to receive(:detach)

      expect { described_class.start }
        .to output("sidebar started (pid 100)\n").to_stdout
      expect(Process).to have_received(:detach).with(100)
    end

    it "reports failure when the instance never registers" do
      allow(PidFile).to receive(:running_pid).and_return(nil)
      allow(described_class).to receive(:spawn_detached).and_return(100)
      allow(described_class).to receive(:sleep)
      allow(Process).to receive(:detach)
      message = "sidebar failed to start - see #{described_class::LOG}\n"

      expect { described_class.start }.to output(message).to_stdout
    end
  end

  describe ".stop" do
    it "reports not running when nothing is registered" do
      allow(PidFile).to receive(:running_pid).and_return(nil)

      expect { described_class.stop }
        .to output("sidebar not running\n").to_stdout
    end

    it "TERMs the instance and clears the pidfile when it exits" do
      allow(PidFile).to receive(:running_pid).and_return(4242, nil, nil)
      allow(PidFile).to receive(:clear)
      allow(Process).to receive(:kill)

      expect { described_class.stop }
        .to output("sidebar stopped (pid 4242)\n").to_stdout
      expect(Process).to have_received(:kill).with("TERM", 4242)
      expect(Process).not_to have_received(:kill).with("KILL", anything)
      expect(PidFile).to have_received(:clear)
    end

    it "escalates to KILL when the process ignores TERM" do
      allow(PidFile).to receive(:running_pid).and_return(4242)
      allow(PidFile).to receive(:clear)
      allow(Process).to receive(:kill)
      allow(described_class).to receive(:sleep)

      expect { described_class.stop }.to output(/sidebar stopped/).to_stdout
      expect(Process).to have_received(:kill).with("TERM", 4242)
      expect(Process).to have_received(:kill).with("KILL", 4242)
    end
  end

  describe ".status" do
    it "reports the running pid" do
      allow(PidFile).to receive(:running_pid).and_return(4242)

      expect { described_class.status }
        .to output("sidebar running (pid 4242)\n").to_stdout
    end

    it "reports when nothing is running" do
      allow(PidFile).to receive(:running_pid).and_return(nil)

      expect { described_class.status }
        .to output("sidebar not running\n").to_stdout
    end
  end

  describe ".restart" do
    it "stops then starts" do
      allow(described_class).to receive(:stop)
      allow(described_class).to receive(:start)

      described_class.restart

      expect(described_class).to have_received(:stop).ordered
      expect(described_class).to have_received(:start).ordered
    end
  end

  describe ".spawn_detached" do
    # Stub the config rather than reading the developer's own: with
    # debug.malloc_check switched on for real, these would otherwise see the
    # debug environment and fail.
    before do
      allow(described_class).to receive(:prepare_log)
      stub_config(malloc_check: false)
    end

    it "spawns setsid + ruby + the launcher, returning the pid" do
      allow(Process).to receive(:spawn).and_return(777)

      expect(described_class.spawn_detached).to eq(777)
      expect(Process).to have_received(:spawn).with(
        {},
        "setsid",
        RbConfig.ruby,
        described_class::BIN,
        in: File::NULL,
        out: [described_class::LOG, "a"],
        err: [:child, :out],
      )
    end

    it "adds the glibc allocator checks when config asks for them" do
      allow(Process).to receive(:spawn).and_return(1)
      stub_config(malloc_check: true)

      described_class.spawn_detached

      expect(Process).to have_received(:spawn)
        .with(described_class::MALLOC_DEBUG_ENV.to_h, any_args)
    end

    it "stamps the log before spawning" do
      allow(Process).to receive(:spawn).and_return(1)

      described_class.spawn_detached

      expect(described_class).to have_received(:prepare_log).with({})
    end

    it "defaults DISPLAY for a non-graphical invocation" do
      allow(Process).to receive(:spawn).and_return(1)

      with_env("DISPLAY", nil) do
        described_class.spawn_detached

        expect(ENV.fetch("DISPLAY")).to eq(":0")
      end
    end

    it "keeps an already-set DISPLAY" do
      allow(Process).to receive(:spawn).and_return(1)

      with_env("DISPLAY", ":7") do
        described_class.spawn_detached

        expect(ENV.fetch("DISPLAY")).to eq(":7")
      end
    end
  end

  describe ".child_env" do
    it "is empty when malloc checking is off" do
      stub_config(malloc_check: false)

      expect(described_class.child_env).to eq({})
    end

    # The preload is the part that's easy to drop and silently inert: since
    # glibc 2.34 the tunable alone does nothing without it.
    it "preloads libc_malloc_debug alongside the tunable" do
      stub_config(malloc_check: true)

      expect(described_class.child_env).to include(
        "LD_PRELOAD" => "libc_malloc_debug.so.0",
        "GLIBC_TUNABLES" => "glibc.malloc.check=3",
      )
    end
  end

  describe ".banner" do
    it "writes a dated line naming a plain launch" do
      path = log_path
      date = /\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \S+/
      stamped = /\A--- sidebar starting #{date} ---\n\z/

      described_class.banner({}, path)

      expect(File.read(path)).to match(stamped)
    end

    it "records that the checks were on" do
      path = log_path

      described_class.banner(described_class::MALLOC_DEBUG_ENV, path)

      expect(File.read(path)).to include("[malloc-check]")
    end

    it "appends rather than replacing" do
      path = log_path
      File.write(path, "earlier run\n")

      described_class.banner({}, path)

      expect(File.read(path)).to start_with("earlier run\n")
    end
  end

  describe ".rotate_log" do
    it "keeps one generation once the log passes the cap" do
      path = log_path
      File.write(path, "x" * (described_class::LOG_MAX_BYTES + 1))

      described_class.rotate_log(path)

      expect(File.exist?(path)).to be(false)
      expect(File.size("#{path}.1")).to eq(described_class::LOG_MAX_BYTES + 1)
    end

    it "leaves a log below the cap alone" do
      path = log_path
      File.write(path, "small\n")

      described_class.rotate_log(path)

      expect(File.read(path)).to eq("small\n")
    end

    it "tolerates a log that doesn't exist yet" do
      expect { described_class.rotate_log(log_path) }.not_to raise_error
    end
  end

  describe ".signal" do
    it "ignores a process that has already exited" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect { described_class.signal(4242, "TERM") }.not_to raise_error
    end
  end
end
