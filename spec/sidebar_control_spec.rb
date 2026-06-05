# frozen_string_literal: true

RSpec.describe SidebarControl do
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

  describe ".spawn_detached" do
    it "spawns setsid + ruby + the launcher, returning the pid" do
      allow(Process).to receive(:spawn).and_return(777)

      expect(described_class.spawn_detached).to eq(777)
      expect(Process).to have_received(:spawn).with(
        "setsid",
        RbConfig.ruby,
        described_class::BIN,
        in: File::NULL,
        out: [described_class::LOG, "a"],
        err: [:child, :out],
      )
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

  describe ".signal" do
    it "ignores a process that has already exited" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect { described_class.signal(4242, "TERM") }.not_to raise_error
    end
  end
end
