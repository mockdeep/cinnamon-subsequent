# frozen_string_literal: true

require "tmpdir"

# Loads the GTK widget classes (for instance_double verification), which calls
# Gtk.init — so this spec needs a display (xvfb-run in CI).
#
# Only the UI boundary (header/window/row) is doubled. Config, TrelloClient, and
# BoardFetch run for real: Config off a temp file, Trello over WebMock-stubbed
# HTTP. Sync.run is stubbed to run inline so the async cascade resolves
# synchronously.
require "app"

RSpec.describe App do
  subject(:app) { described_class.new(config, header: header, window: window) }

  let(:header) { instance_double(UI::Header)                }
  let(:window) { instance_double(UI::DockWindow)            }
  let(:config) { make_config(board_id: "b1", lane_id: "l1") }

  # Captures the blocks App wires onto its collaborators so tests can fire a
  # board/lane/refresh/toggle the way a real user interaction would.
  let(:callbacks) { {} }

  around do |example|
    Dir.mktmpdir do |dir|
      @config_dir = dir
      example.run
    end
  end

  # A real Config on disk, with credentials matching the api_url helper so the
  # real TrelloClient App builds from it hits our stubs.
  def make_config(key: TrelloHelpers::TEST_KEY, token: TrelloHelpers::TEST_TOKEN, limit: nil, **selection)
    data = {
      "trello" => { "key" => key, "token" => token },
      "selection" => {
        "board_id" => selection[:board_id],
        "lane_id" => selection[:lane_id],
      },
      "view" => { "item_limit" => limit },
    }
    path = File.join(@config_dir, "config.json")
    File.write(path, JSON.generate(data))
    Config.new(path)
  end

  def stub_boards(boards)
    stub_request(:get, api_url("/members/me/boards", fields: "name", filter: "open"))
      .to_return(body: boards.to_json)
  end

  def stub_lists(board_id, lists)
    stub_request(:get, api_url("/boards/#{board_id}/lists", fields: "name", filter: "open"))
      .to_return(body: lists.to_json)
  end

  def cards_url(lane_id)
    api_url(
      "/lists/#{lane_id}/cards",
      fields: "name",
      filter: "open",
      checklists: "all",
      checklist_fields: "name,pos",
      checkItems: "all",
      checkItem_fields: "name,state,pos",
    )
  end

  def stub_cards(lane_id, cards)
    stub_request(:get, cards_url(lane_id)).to_return(body: cards.to_json)
  end

  before do
    allow(header).to receive(:on_board_change) { |&block| callbacks[:board] = block }
    allow(header).to receive(:on_lane_change) { |&block| callbacks[:lane] = block }
    allow(header).to receive(:on_refresh) { |&block| callbacks[:refresh] = block }
    allow(header).to receive(:set_boards)
    allow(header).to receive(:set_lanes)
    allow(header).to receive(:busy=)
    allow(window).to receive(:on_item_toggle) { |&block| callbacks[:toggle] = block }
    allow(window).to receive(:on_tag_change) { |&block| callbacks[:tag] = block }
    allow(window).to receive(:on_limit_change) { |&block| callbacks[:limit] = block }
    allow(window).to receive(:set_tags)
    allow(window).to receive(:item_limit=)
    allow(window).to receive(:show_all)
    allow(window).to receive(:apply_dock_behaviour)
    allow(window).to receive(:render)
    allow(window).to receive(:render_loading)

    # Sync delivers asynchronously (worker thread → GLib::Idle). Run it inline
    # so the cascade resolves synchronously while preserving Sync's contract:
    # on_success only on success, a StandardError routed to on_error.
    allow(Sync).to receive(:run) do |work, on_success:, on_error: nil|
      value = work.call
    rescue StandardError => e
      on_error ? on_error.call(e) : raise
    else
      on_success.call(value)
    end
  end

  describe "default collaborators" do
    it "builds a real header, dock window, and Trello client" do
      expect { described_class.new(make_config(board_id: "b1", lane_id: "l1")) }
        .not_to raise_error
    end
  end

  describe "#start" do
    before do
      stub_boards([api_board("id" => "b1")])
      stub_lists("b1", [api_list("id" => "l1")])
      stub_cards("l1", [])
    end

    it "shows and docks the window" do
      app.start

      expect(window).to have_received(:show_all)
      expect(window).to have_received(:apply_dock_behaviour)
    end

    it "runs the full board → lane → fetch cascade" do
      app.start

      expect(header).to have_received(:set_boards).with([api_board("id" => "b1")], "b1")
      expect(header).to have_received(:set_lanes).with([api_list("id" => "l1")], "l1")
      expect(a_request(:get, cards_url("l1"))).to have_been_made
    end

    it "persists the resolved board and lane to disk" do
      app.start

      expect(config.board_id).to eq("b1")
      expect(config.lane_id).to eq("l1")
      expect(Config.new(config.path).lane_id).to eq("l1")
    end

    it "renders the fetched result and toggles busy around the work" do
      app.start

      expect(window).to have_received(:render)
        .with(have_attributes(empty_reason: "This lane has no cards."))
      # busy(true) once per cascade step (boards/lanes/fetch); cleared once at the end.
      expect(header).to have_received(:busy=).with(true).at_least(:once)
      expect(header).to have_received(:busy=).with(false).once
    end
  end

  context "when Trello is not configured" do
    let(:config) { make_config(key: nil, token: nil) }

    it "renders the setup hint and skips the cascade" do
      app.start

      expect(window).to have_received(:render)
        .with(have_attributes(empty_reason: a_string_including("key/token missing")))
      expect(header).not_to have_received(:set_boards)
    end

    it "ignores a refresh, since there's no client to load from" do
      app

      expect { callbacks[:refresh].call }.not_to raise_error
      expect(header).not_to have_received(:set_boards)
    end
  end

  context "when no board is persisted yet" do
    let(:config) { make_config(board_id: nil, lane_id: nil) }

    before do
      stub_boards([api_board("id" => "b1")])
      stub_lists("b1", [api_list("id" => "l1")])
      stub_cards("l1", [])
    end

    it "defaults to the first board Trello returns" do
      app.start

      expect(header).to have_received(:set_boards).with([api_board("id" => "b1")], "b1")
      expect(a_request(:get, api_url("/boards/b1/lists", fields: "name", filter: "open")))
        .to have_been_made
    end
  end

  context "when there are no boards" do
    let(:config) { make_config(board_id: nil, lane_id: nil) }

    before { stub_boards([]) }

    it "reports that no boards are available" do
      app.start

      expect(window).to have_received(:render)
        .with(have_attributes(empty_reason: "No boards available."))
    end
  end

  context "when the board has no lanes" do
    let(:config) { make_config(board_id: "b1", lane_id: nil) }

    before do
      stub_boards([api_board("id" => "b1")])
      stub_lists("b1", [])
    end

    it "reports that the board has no lanes" do
      app.start

      expect(window).to have_received(:render)
        .with(have_attributes(empty_reason: "This board has no lanes."))
    end
  end

  context "when Trello returns an error" do
    before do
      stub_request(:get, api_url("/members/me/boards", fields: "name", filter: "open"))
        .to_return(status: 500)
    end

    it "renders the error as the empty state" do
      app.start

      expect(window).to have_received(:render)
        .with(have_attributes(empty_reason: a_string_starting_with("Trello error:")))
    end
  end

  describe "choosing a board" do
    before do
      stub_lists("b2", [api_list("id" => "l9")])
      stub_cards("l9", [])
      app
    end

    it "reloads lanes for that board, defaulting to its first lane" do
      callbacks[:board].call("b2")

      expect(header).to have_received(:set_lanes).with([api_list("id" => "l9")], "l9")
      expect(config.board_id).to eq("b2")
      expect(config.lane_id).to eq("l9")
    end
  end

  describe "choosing a lane" do
    before do
      stub_cards("l2", [])
      app
    end

    it "persists the lane and refetches" do
      callbacks[:lane].call("l2")

      expect(config.lane_id).to eq("l2")
      expect(Config.new(config.path).lane_id).to eq("l2")
      expect(a_request(:get, cards_url("l2"))).to have_been_made
    end
  end

  describe "refreshing" do
    before do
      stub_boards([api_board("id" => "b1")])
      stub_lists("b1", [api_list("id" => "l1")])
      stub_cards("l1", [])
      app
    end

    it "re-runs the board cascade" do
      callbacks[:refresh].call

      expect(header).to have_received(:set_boards).with([api_board("id" => "b1")], "b1")
    end
  end

  describe "toggling an item" do
    let(:row) { instance_double(UI::ItemRow) }
    let(:item) do
      BoardFetch::Item.new(
        id: "i1",
        card_id: "c1",
        checklist_id: "cl1",
        name: "Thing",
        state: "incomplete",
      )
    end

    before do
      allow(row).to receive(:settle)
      allow(row).to receive(:fail)
      app
    end

    it "pushes complete and settles the row on success" do
      toggle_url = api_url("/cards/c1/checkItem/i1", state: "complete")
      stub_request(:put, toggle_url).to_return(body: "{}")

      callbacks[:toggle].call(row, item, "complete")

      expect(a_request(:put, toggle_url)).to have_been_made
      expect(row).to have_received(:settle).with("complete")
    end

    it "pushes incomplete without touching busy state" do
      toggle_url = api_url("/cards/c1/checkItem/i1", state: "incomplete")
      stub_request(:put, toggle_url).to_return(body: "{}")

      callbacks[:toggle].call(row, item, "incomplete")

      expect(a_request(:put, toggle_url)).to have_been_made
      expect(header).not_to have_received(:busy=)
    end

    it "fails the row when the push errors" do
      toggle_url = api_url("/cards/c1/checkItem/i1", state: "complete")
      stub_request(:put, toggle_url).to_return(status: 400)

      callbacks[:toggle].call(row, item, "complete")

      expect(row).to have_received(:fail).with(instance_of(TrelloClient::Error))
    end
  end

  describe "tag filtering" do
    # Capture what the window is told to render / which tags it's given, so we
    # can assert on the *latest* state after a sequence of interactions.
    let(:renders) { [] }
    let(:tag_updates) { [] }

    def tagged_card(id: "c1")
      checklists = [
        api_checklist(
          "id" => "cl1",
          "name" => "Home @home",
          "checkItems" => [api_item("id" => "i1", "name" => "Milk")],
        ),
        api_checklist(
          "id" => "cl2",
          "name" => "Work @work",
          "checkItems" => [api_item("id" => "i2", "name" => "Email")],
        ),
      ]
      api_card("id" => id, "name" => "Card", "checklists" => checklists)
    end

    before do
      allow(window).to receive(:render) { |result| renders << result }
      allow(window).to receive(:set_tags) { |tags, selected| tag_updates << [tags, selected] }
      stub_boards([api_board("id" => "b1")])
      stub_lists("b1", [api_list("id" => "l1")])
      stub_request(:get, cards_url("l1")).to_return(body: [tagged_card].to_json)
      app.start
    end

    it "populates the tag bar from the whole lane, unselected" do
      tags, selected = tag_updates.last

      expect(tags.map(&:name)).to eq(["@home", "@work"])
      expect(selected).to eq(Set.new)
    end

    it "renders the default first-card view before any tag is chosen" do
      expect(renders.last.groups.map(&:name)).to eq(["Home @home", "Work @work"])
    end

    it "renders matching items under a tag heading when a tag is selected" do
      callbacks[:tag].call(Set["@home"])

      expect(renders.last.groups.map(&:name)).to eq(["@home"])
      expect(renders.last.groups.first.items.map(&:name)).to eq(["Milk"])
    end

    it "returns to the default view when the selection is cleared" do
      callbacks[:tag].call(Set["@home"])
      callbacks[:tag].call(Set.new)

      expect(renders.last.groups.map(&:name)).to eq(["Home @home", "Work @work"])
    end

    it "keeps the tag filter across a refresh" do
      callbacks[:tag].call(Set["@home"])
      callbacks[:refresh].call

      expect(tag_updates.last.last).to eq(Set["@home"])
      expect(renders.last.groups.map(&:name)).to eq(["@home"])
    end

    it "resets the tag filter when switching lane" do
      callbacks[:tag].call(Set["@home"])
      stub_request(:get, cards_url("l2")).to_return(body: [tagged_card].to_json)
      callbacks[:lane].call("l2")

      expect(tag_updates.last.last).to eq(Set.new)
      expect(renders.last.groups.map(&:name)).to eq(["Home @home", "Work @work"])
    end
  end

  describe "the per-list item limit" do
    let(:renders) { [] }

    # One card whose single checklist has three items, so a cap of 2 truncates.
    def big_card
      checklist = api_checklist(
        "id" => "cl1",
        "name" => "Big @big",
        "checkItems" => (1..3).map { |n| api_item("id" => "i#{n}", "name" => "I#{n}", "pos" => n) },
      )
      api_card("id" => "c1", "name" => "Card", "checklists" => [checklist])
    end

    before do
      allow(window).to receive(:render) { |result| renders << result }
      stub_boards([api_board("id" => "b1")])
      stub_lists("b1", [api_list("id" => "l1")])
      stub_request(:get, cards_url("l1")).to_return(body: [big_card].to_json)
    end

    it "tells the window the persisted limit on construction" do
      config = make_config(board_id: "b1", lane_id: "l1", limit: 4)
      described_class.new(config, header: header, window: window)

      expect(window).to have_received(:item_limit=).with(4)
    end

    it "applies a persisted limit to the fetched view" do
      config = make_config(board_id: "b1", lane_id: "l1", limit: 2)
      described_class.new(config, header: header, window: window).start

      expect(renders.last.groups.first.items.map(&:name)).to eq(["I1", "I2"])
      expect(renders.last.groups.first.hidden_count).to eq(1)
    end

    it "caps the rendered groups and persists a newly chosen limit" do
      app.start
      callbacks[:limit].call(2)

      expect(renders.last.groups.first.items.size).to eq(2)
      expect(config.item_limit).to eq(2)
      expect(Config.new(config.path).item_limit).to eq(2)
    end

    it "restores the full list when the cap is cleared" do
      app.start
      callbacks[:limit].call(2)
      callbacks[:limit].call(nil)

      expect(renders.last.groups.first.items.size).to eq(3)
      expect(Config.new(config.path).item_limit).to be_nil
    end

    it "caps tag-filtered groups too" do
      app.start
      callbacks[:limit].call(2)
      callbacks[:tag].call(Set["@big"])

      expect(renders.last.groups.map(&:name)).to eq(["@big"])
      expect(renders.last.groups.first.items.size).to eq(2)
    end

    it "keeps the limit across a refresh" do
      app.start
      callbacks[:limit].call(2)
      callbacks[:refresh].call

      expect(renders.last.groups.first.items.size).to eq(2)
    end

    it "persists but renders nothing when no lane has loaded yet" do
      app
      callbacks[:limit].call(2)

      expect(window).not_to have_received(:render)
      expect(Config.new(config.path).item_limit).to eq(2)
    end
  end

  describe "toggling tags before a lane has loaded" do
    it "is a safe no-op, with nothing to re-render yet" do
      app
      callbacks[:tag].call(Set["@home"])

      expect(window).not_to have_received(:render)
    end
  end
end
