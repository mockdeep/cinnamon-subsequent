# frozen_string_literal: true

require "json"
require "sessions/store"
require "tmpdir"

RSpec.describe Sessions::Store do
  # Everything alive by default, so the reaper doesn't interfere unless a test
  # opts into a dead pid.
  subject(:store) { described_class.new(@dir, alive: ->(_pid) { true }) }

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  def write_session(name, **fields)
    data = {
      "session_id" => name,
      "pid" => 4242,
    }.merge(fields.transform_keys(&:to_s))
    File.write(File.join(@dir, "#{name}.json"), JSON.generate(data))
  end

  describe "#sessions" do
    it "reads each state file into a Session" do
      write_session(
        "a",
        theme_color: "#ffaa00",
        status: "active",
        project_name: "proj",
        window_id: "123",
      )

      session = store.sessions.first

      expect(session).to have_attributes(
        id: "a", color: "#ffaa00", status: "active",
        project: "proj", window_id: 123,
      )
    end

    it "defaults a missing colour, status, and project name" do
      write_session("a", theme_color: nil, project_name: "")

      expect(store.sessions.first).to have_attributes(
        color: described_class::DEFAULT_COLOR, status: "idle", project: "?",
      )
    end

    it "parses a missing/blank window id as nil" do
      write_session("a", window_id: "")

      expect(store.sessions.first.window_id).to be_nil
    end

    it "reaps and skips a session whose process has exited" do
      write_session("dead", pid: 999)
      file = File.join(@dir, "dead.json")
      store = described_class.new(@dir, alive: ->(pid) { pid != 999 })

      expect(store.sessions).to be_empty
      expect(File).not_to exist(file)
    end

    it "keeps a session that has no pid (can't prove it's dead)" do
      write_session("a", pid: nil)

      expect(store.sessions.map(&:id)).to eq(["a"])
    end

    it "skips malformed JSON without raising" do
      File.write(File.join(@dir, "bad.json"), "{not json")
      write_session("good")

      expect(store.sessions.map(&:id)).to eq(["good"])
    end

    it "orders by window id then session id, nil windows last" do
      write_session("z", window_id: "10")
      write_session("a", window_id: "10")
      write_session("loose", window_id: "")

      expect(store.sessions.map(&:id)).to eq(["a", "z", "loose"])
    end

    it "is empty when the state directory doesn't exist" do
      store = described_class.new(File.join(@dir, "nope"))

      expect(store.sessions).to be_empty
    end
  end
end
