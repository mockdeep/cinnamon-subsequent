# frozen_string_literal: true

require "json"
require "sessions/focus"

RSpec.describe Sessions::Focus do
  describe ".call" do
    it "runs the hook's focus action with the session id on stdin" do
      calls = []
      runner = ->(hook, payload) { calls << [hook, payload] }

      described_class.call("sess-1", hook: "/hook", runner: runner).join

      expect(calls).to eq([["/hook", JSON.dump(session_id: "sess-1")]])
    end

    it "is a no-op for a nil or empty session id" do
      calls = []
      runner = ->(*args) { calls << args }

      described_class.call(nil, runner: runner)
      described_class.call("", runner: runner)

      expect(calls).to be_empty
    end

    it "resolves the hook to this repo's bin/ by default" do
      expect(described_class::HOOK).to end_with("/bin/claude-session-tracker")
    end
  end
end
