# frozen_string_literal: true

require "tmpdir"

RSpec.describe Config do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def path
    File.join(@dir, "config.json")
  end

  def write_config(data)
    File.write(path, JSON.generate(data))
  end

  describe ".load" do
    it "defaults the path to DEFAULT_PATH" do
      expect(described_class.load.path).to eq(described_class::DEFAULT_PATH)
    end
  end

  describe "defaults" do
    it "falls back to the built-in defaults when no file exists" do
      config = described_class.new(path)

      expect(config.trello_key).to be_nil
      expect(config.trello_token).to be_nil
      expect(config.board_id).to be_nil
      expect(config.lane_id).to be_nil
      expect(config.edge).to eq(:right)
      expect(config.width).to eq(320)
    end

    it "reads values from the file, deep-merged over the defaults" do
      write_config(
        "trello" => { "key" => "abc", "token" => "xyz" },
        "selection" => { "board_id" => "b1" },
        "appearance" => { "edge" => "left" },
      )

      config = described_class.new(path)

      expect(config.trello_key).to eq("abc")
      expect(config.trello_token).to eq("xyz")
      expect(config.board_id).to eq("b1")
      # not in the file → kept from defaults
      expect(config.lane_id).to be_nil
      expect(config.edge).to eq(:left)
      expect(config.width).to eq(320)
    end

    it "keeps the default when the file holds an explicit nil" do
      write_config("appearance" => { "width" => nil })

      expect(described_class.new(path).width).to eq(320)
    end
  end

  describe "#board_id= / #lane_id=" do
    it "updates the in-memory selection" do
      config = described_class.new(path)

      config.board_id = "b9"
      config.lane_id = "l9"

      expect(config.board_id).to eq("b9")
      expect(config.lane_id).to eq("l9")
    end
  end

  describe "#exist?" do
    it "is false with no file and true once one is present" do
      config = described_class.new(path)
      expect(config.exist?).to be(false)

      write_config({})
      expect(config.exist?).to be(true)
    end
  end

  describe "#configured?" do
    it "is true only when both key and token are present" do
      write_config("trello" => { "key" => "abc", "token" => "xyz" })
      expect(described_class.new(path)).to be_configured
    end

    it "is false when the token is missing" do
      write_config("trello" => { "key" => "abc", "token" => nil })
      expect(described_class.new(path)).not_to be_configured
    end

    it "is false when a credential is blank" do
      write_config("trello" => { "key" => "", "token" => "xyz" })
      expect(described_class.new(path)).not_to be_configured
    end
  end

  describe "#setup_hint" do
    it "points at the missing file" do
      expect(described_class.new(path).setup_hint)
        .to match(/No config file at .*config\.json/)
    end

    it "flags missing credentials when the file exists" do
      write_config("trello" => { "key" => "abc" })

      expect(described_class.new(path).setup_hint)
        .to match(/key\/token missing/)
    end

    it "is nil once fully configured" do
      write_config("trello" => { "key" => "abc", "token" => "xyz" })

      expect(described_class.new(path).setup_hint).to be_nil
    end
  end

  describe "#save" do
    it "writes pretty JSON the next load reads back" do
      config = described_class.new(path)
      config.board_id = "b1"
      config.lane_id = "l1"

      config.save

      reloaded = described_class.new(path)
      expect(reloaded.board_id).to eq("b1")
      expect(reloaded.lane_id).to eq("l1")
      expect(File.read(path)).to end_with("\n")
    end

    it "locks the file to 0600 and its directory to 0700" do
      nested = File.join(@dir, "nested", "config.json")

      Config.new(nested).save

      expect(File.stat(nested).mode & 0o777).to eq(0o600)
      expect(File.stat(File.dirname(nested)).mode & 0o777).to eq(0o700)
    end

    it "returns self" do
      config = described_class.new(path)
      expect(config.save).to be(config)
    end
  end

  describe "invalid JSON" do
    it "raises a clear error" do
      File.write(path, "{ not json")

      expect { described_class.new(path) }
        .to raise_error(/is not valid JSON/)
    end
  end
end
