# frozen_string_literal: true

require "auto_refresh"

RSpec.describe AutoRefresh do
  subject(:auto_refresh) { described_class.new(interval: 900, clock: clock) }

  # A hand-cranked clock, so a test can jump forward fifteen minutes without
  # taking fifteen minutes. Boxed in a hash so the lambda reads the live value.
  let(:time)  { { seconds: 1000.0 }         }
  let(:clock) { -> { time.fetch(:seconds) } }
  let(:fires) { []                          }

  def advance(by) = time[:seconds] = time.fetch(:seconds) + by

  before { auto_refresh.on_refresh { fires << :fired } }

  it "doesn't fire before the interval has elapsed" do
    advance(899)
    auto_refresh.tick

    expect(fires).to be_empty
  end

  it "fires once the interval has elapsed" do
    advance(900)
    auto_refresh.tick

    expect(fires.size).to eq(1)
  end

  it "keeps firing every interval while nothing is touched" do
    3.times do
      advance(900)
      auto_refresh.tick
    end

    expect(fires.size).to eq(3)
  end

  it "waits a full interval after firing, not just until the next tick" do
    advance(900)
    auto_refresh.tick

    advance(30)
    auto_refresh.tick

    expect(fires.size).to eq(1)
  end

  it "pushes the next fire out when the user interacts" do
    advance(899)
    auto_refresh.touch
    advance(899)
    auto_refresh.tick

    expect(fires).to be_empty
  end

  context "when the interval is nil" do
    subject(:auto_refresh) { described_class.new(interval: nil, clock: clock) }

    it "is disabled and never fires" do
      advance(100_000)
      auto_refresh.tick

      expect(auto_refresh).not_to be_enabled
      expect(fires).to be_empty
    end

    it "doesn't even start a timer" do
      allow(GLib::Timeout).to receive(:add)

      auto_refresh.start

      expect(GLib::Timeout).not_to have_received(:add)
    end
  end
end
