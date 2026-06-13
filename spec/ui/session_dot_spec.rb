# frozen_string_literal: true

require "sessions/store"
require "ui/session_dot"

RSpec.describe UI::SessionDot do
  def session(**overrides)
    Sessions::Session.new(
      id: "a",
      color: "#cc241d",
      status: "idle",
      project: "proj",
      window_id: 1,
      **overrides,
    )
  end

  describe "#pulsing?" do
    it "is true only while the session is active" do
      expect(
        described_class.new(
          session(status: "active"),
          focused: false,
        ),
      ).to be_pulsing
      expect(
        described_class.new(
          session(status: "idle"),
          focused: false,
        ),
      ).not_to be_pulsing
    end
  end

  describe "click" do
    it "fires on_click when the dot is reactive" do
      dot = described_class.new(session, focused: false)
      fired = false
      dot.on_click { fired = true }

      dot.signal_emit("button-press-event", Gdk::EventButton.new(:button_press))

      expect(fired).to be(true)
    end
  end

  describe "#rgb" do
    subject(:dot) { described_class.new(session, focused: false) }

    it "parses a #rrggbb colour to 0..1 floats" do
      expect(dot.send(:rgb, "#ff8000")).to eq([1.0, 128 / 255.0, 0.0])
    end

    it "falls back to the default colour for garbage" do
      expect(
        dot.send(
          :rgb,
          "not-a-colour",
        ),
      ).to eq(
        dot.send(
          :rgb,
          described_class::DEFAULT_COLOR,
        ),
      )
    end
  end
end
