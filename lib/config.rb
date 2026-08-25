# frozen_string_literal: true

require "json"
require "fileutils"

# Loads and persists ~/.config/cinnamon-subsequent/config.json.
# Holds Trello credentials, the selected board/lane, and appearance/view prefs.
# The file is written 0600 (creds live here) under a 0700 directory.
class Config
  DEFAULT_DIR = File.join(
    ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config")),
    "cinnamon-subsequent"
  )
  DEFAULT_PATH = File.join(DEFAULT_DIR, "config.json")

  DEFAULT_FONT_SIZE = 13
  DEFAULT_REFRESH_INTERVAL_MINUTES = 15
  DEFAULT_RANDOM_COUNT = 5
  # What the dice dropdown offers; kept here too so a hand-edited count can be
  # validated without loading any GTK.
  RANDOM_COUNTS = (1..9)

  DEFAULTS = {
    "trello"     => { "key" => nil, "token" => nil },
    "selection"  => { "board_id" => nil, "lane_id" => nil },
    "appearance" => { "edge" => "right", "width" => 320, "font_size" => DEFAULT_FONT_SIZE },
    "debug"      => { "malloc_check" => false },
    "view"       => {
      "item_limit" => nil,
      "random_count" => DEFAULT_RANDOM_COUNT,
      "refresh_interval_minutes" => DEFAULT_REFRESH_INTERVAL_MINUTES
    }
  }.freeze

  def self.load(path = DEFAULT_PATH)
    new(path)
  end

  attr_reader :path

  def initialize(path = DEFAULT_PATH)
    @path = path
    # deep_dup the defaults first: Hash#merge keeps base's value object for any
    # section the file omits, so without this every Config would share (and a
    # setter would mutate) DEFAULTS' nested hashes.
    @data = deep_merge(deep_dup(DEFAULTS), read_file)
  end

  def trello_key  = dig("trello", "key")
  def trello_token = dig("trello", "token")
  def board_id    = dig("selection", "board_id")
  def lane_id     = dig("selection", "lane_id")
  def edge        = dig("appearance", "edge").to_sym
  def width       = dig("appearance", "width")

  # Base UI font size in px, as set by the footer's A-/A+ steppers. Falls back
  # to the default if the file was hand-edited to something unusable.
  def font_size
    value = dig("appearance", "font_size")
    value.is_a?(Integer) && value.positive? ? value : DEFAULT_FONT_SIZE
  end

  # Per-list cap on rendered items; nil (or anything but a positive integer,
  # in case the file was hand-edited) means unlimited.
  def item_limit
    value = dig("view", "item_limit")
    value.is_a?(Integer) && value.positive? ? value : nil
  end

  # How many items the dice button picks. Only the count is remembered — random
  # mode itself always starts off, so a launch shows the real list. Anything
  # outside the dropdown's 1-9 (hand-edited) falls back to the default.
  def random_count
    value = dig("view", "random_count")
    value.is_a?(Integer) && RANDOM_COUNTS.cover?(value) ? value : DEFAULT_RANDOM_COUNT
  end

  # Minutes of no interaction before the list quietly refetches itself, given in
  # seconds (what AutoRefresh wants). Set the key to 0 to switch auto-refresh
  # off; a non-integer (hand-edited to nonsense) falls back to the default.
  # Note `null` won't disable it — an explicit null loses to the default in
  # deep_merge, so 0 is the off switch.
  def refresh_interval
    value = dig("view", "refresh_interval_minutes")
    minutes = value.is_a?(Integer) ? value : DEFAULT_REFRESH_INTERVAL_MINUTES
    minutes.positive? ? minutes * 60 : nil
  end

  # Launch the sidebar under glibc's allocator checks? A diagnostic for heap
  # corruption from the Xlib/GObject side, off by default: it slows every
  # allocation and turns a survivable inconsistency into an immediate abort.
  # Read by SidebarControl at spawn time, so it only takes effect on a restart.
  # Anything but a literal `true` (including a hand-edited string) reads as off.
  def malloc_check? = dig("debug", "malloc_check") == true

  def board_id=(value)
    @data["selection"]["board_id"] = value
  end

  def lane_id=(value)
    @data["selection"]["lane_id"] = value
  end

  def item_limit=(value)
    @data["view"]["item_limit"] = value
  end

  def random_count=(value)
    @data["view"]["random_count"] = value
  end

  def font_size=(value)
    @data["appearance"]["font_size"] = value
  end

  def exist?      = File.exist?(path)
  def configured? = !blank?(trello_key) && !blank?(trello_token)

  # One-line, user-facing reason the app can't talk to Trello yet (or nil).
  def setup_hint
    return "No config file at #{path} — copy config.example.json there and fill in your Trello key/token." unless exist?
    return "Trello key/token missing in #{path}." unless configured?

    nil
  end

  def save
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    File.write(path, JSON.pretty_generate(@data) + "\n")
    File.chmod(0o600, path)
    self
  end

  private

  def dig(*keys) = @data.dig(*keys)

  def blank?(value) = value.nil? || (value.respond_to?(:empty?) && value.empty?)

  def read_file
    return {} unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    raise "Config at #{path} is not valid JSON: #{e.message}"
  end

  def deep_dup(hash)
    hash.each_with_object({}) do |(key, value), copy|
      copy[key] = value.is_a?(Hash) ? deep_dup(value) : value
    end
  end

  def deep_merge(base, override)
    base.merge(override) do |_key, base_val, over_val|
      if base_val.is_a?(Hash) && over_val.is_a?(Hash)
        deep_merge(base_val, over_val)
      elsif over_val.nil?
        base_val
      else
        over_val
      end
    end
  end
end
