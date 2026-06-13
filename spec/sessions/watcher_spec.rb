# frozen_string_literal: true

require "sessions/watcher"

RSpec.describe Sessions::Watcher do
  subject(:watcher) do
    described_class.new(store: store, active_window: active_window)
  end

  let(:session)       { Sessions::Session.new(id: "a", color: "#fff", status: "idle", project: "p", window_id: 7) }
  let(:store)         { instance_double(Sessions::Store, sessions: [session])                                     }
  let(:active_window) { class_double(X11::ActiveWindow, current: 7)                                               }

  it "fires on_change with the sessions and focused window on the first tick" do
    captured = nil
    watcher.on_change { |sessions, focused| captured = [sessions, focused] }

    watcher.tick

    expect(captured).to eq([[session], 7])
  end

  it "doesn't fire again when nothing visible changed" do
    fired = 0
    watcher.on_change { |_s, _f| fired += 1 }

    2.times { watcher.tick }

    expect(fired).to eq(1)
  end

  it "fires again when the focused window changes" do
    fired = 0
    watcher.on_change { |_s, _f| fired += 1 }
    watcher.tick

    allow(active_window).to receive(:current).and_return(99)
    watcher.tick

    expect(fired).to eq(2)
  end

  it "treats an active-window lookup failure as no focus" do
    allow(active_window).to receive(:current).and_raise("X is down")
    captured = :unset
    watcher.on_change { |_s, focused| captured = focused }

    watcher.tick

    expect(captured).to be_nil
  end
end
