# frozen_string_literal: true

RSpec.describe BoardFetch do
  subject(:lane_view) { described_class.new(client, config).call }

  let(:client) { instance_double(TrelloClient) }
  let(:config) { instance_double(Config, lane_id: "lane-1") }

  # A card carrying nested checklists, as cards_with_checklists returns them.
  def card_with(id:, name: "Card", checklists: [])
    api_card("id" => id, "name" => name, "checklists" => checklists)
  end

  def stub_cards(cards)
    allow(client).to receive(:cards_with_checklists)
      .with("lane-1").and_return(cards)
  end

  describe "empty states" do
    it "reports when no lane is selected (nil)" do
      allow(config).to receive(:lane_id).and_return(nil)

      expect(lane_view.default_result.empty_reason).to eq("No lane selected yet.")
      expect(lane_view.tags).to be_empty
    end

    it "reports when no lane is selected (blank string)" do
      allow(config).to receive(:lane_id).and_return("")

      expect(lane_view.default_result.empty_reason).to eq("No lane selected yet.")
    end

    it "reports when the lane has no cards" do
      stub_cards([])

      expect(lane_view.default_result.empty_reason).to eq("This lane has no cards.")
      expect(lane_view.tags).to be_empty
    end

    it "reports all-caught-up, naming the card, when the first card is done" do
      done = api_checklist("checkItems" => [api_item("state" => "complete")])
      stub_cards([card_with(id: "c1", name: "My Card", checklists: [done])])

      expect(lane_view.default_result.empty_reason).to eq("Nothing left — all caught up.")
      expect(lane_view.default_result.card_name).to eq("My Card")
      expect(lane_view.default_result.groups).to be_empty
    end
  end

  describe "the default (first-card) view" do
    subject(:result) { lane_view.default_result }

    let(:checklists) do
      [
        api_checklist(
          "id" => "cl-2",
          "name" => "Second",
          "pos" => 2,
          "checkItems" => [api_item("id" => "b1", "name" => "B1", "pos" => 1)],
        ),
        api_checklist(
          "id" => "cl-1",
          "name" => "First",
          "pos" => 1,
          "checkItems" => [
            api_item("id" => "a2", "name" => "A2", "pos" => 2),
            api_item("id" => "a1", "name" => "A1", "pos" => 1),
            api_item("id" => "ax", "name" => "Done", "state" => "complete", "pos" => 3),
          ],
        ),
      ]
    end

    let(:cards) do
      [
        card_with(id: "card-1", name: "My Card", checklists: checklists),
        card_with(id: "card-2", name: "Other", checklists: []),
      ]
    end

    before { stub_cards(cards) }

    it "uses the first card only" do
      expect(result.card_name).to eq("My Card")
    end

    it "orders checklists by pos" do
      expect(result.groups.map(&:name)).to eq(["First", "Second"])
    end

    it "keeps only incomplete items, ordered by pos" do
      expect(result.groups.first.items.map(&:name)).to eq(["A1", "A2"])
    end

    it "maps each item with its card and checklist ids" do
      expect(result.groups.first.items.first).to have_attributes(
        id: "a1",
        card_id: "card-1",
        checklist_id: "cl-1",
        name: "A1",
        state: "incomplete",
      )
    end
  end

  describe "the tag index" do
    let(:first_card) do
      card_with(
        id: "card-1",
        name: "First",
        checklists: [
          api_checklist(
            "id" => "cl-1",
            "name" => "Groceries @home",
            "checkItems" => [api_item("id" => "i1", "name" => "Milk")],
          ),
          api_checklist(
            "id" => "cl-2",
            "name" => "Standup @work @urgent",
            "checkItems" => [api_item("id" => "i2", "name" => "Notes")],
          ),
        ],
      )
    end

    let(:second_card) do
      card_with(
        id: "card-2",
        name: "Second",
        checklists: [
          api_checklist(
            "id" => "cl-3",
            "name" => "Errands @home",
            "checkItems" => [
              api_item("id" => "i3", "name" => "Bank"),
              api_item("id" => "i4", "name" => "Sealed", "state" => "complete"),
            ],
          ),
          api_checklist(
            "id" => "cl-4",
            "name" => "Untagged list",
            "checkItems" => [api_item("id" => "i5", "name" => "Loose")],
          ),
          api_checklist(
            "id" => "cl-5",
            "name" => "Archived @archived",
            "checkItems" => [api_item("id" => "i6", "state" => "complete")],
          ),
        ],
      )
    end

    before { stub_cards([first_card, second_card]) }

    it "lists tags across all cards, sorted, with incomplete-item counts" do
      expect(lane_view.tags.map { |t| [t.name, t.item_count] })
        .to eq([["@home", 2], ["@urgent", 1], ["@work", 1]])
    end

    it "ignores checklists with no @tag in their name" do
      expect(lane_view.tags.map(&:name)).not_to include("Untagged list")
    end

    it "omits a tag whose only checklist has no incomplete items" do
      expect(lane_view.tags.map(&:name)).not_to include("@archived")
    end

    it "gathers a tag's incomplete items from every matching checklist" do
      result = lane_view.result_for(["@home"])

      expect(result.groups.map(&:name)).to eq(["@home"])
      expect(result.groups.first.items.map(&:name)).to eq(["Milk", "Bank"])
    end

    it "excludes completed items from a tag's list" do
      ids = lane_view.result_for(["@home"]).groups.first.items.map(&:id)

      expect(ids).not_to include("i4")
    end

    it "gives each selected tag its own group, in name order" do
      result = lane_view.result_for(["@work", "@home"])

      expect(result.groups.map(&:name)).to eq(["@home", "@work"])
    end

    it "falls back to the default view when nothing is selected" do
      expect(lane_view.result_for([])).to equal(lane_view.default_result)
    end

    it "ignores selected tags that no longer exist (carried across a refresh)" do
      result = lane_view.result_for(["@home", "@gone"])

      expect(result.groups.map(&:name)).to eq(["@home"])
    end
  end

  describe "the per-group item limit" do
    let(:checklists) do
      [
        api_checklist(
          "id" => "cl-1",
          "name" => "Big @big",
          "pos" => 1,
          "checkItems" => (1..4).map { |n| api_item("id" => "b#{n}", "name" => "B#{n}", "pos" => n) },
        ),
        api_checklist(
          "id" => "cl-2",
          "name" => "Small",
          "pos" => 2,
          "checkItems" => [api_item("id" => "s1", "name" => "S1")],
        ),
      ]
    end

    before { stub_cards([card_with(id: "card-1", checklists: checklists)]) }

    it "caps each group at its first N items and records what was cut" do
      group = lane_view.result_for([], limit: 2).groups.first

      expect(group.items.map(&:name)).to eq(["B1", "B2"])
      expect(group.hidden_count).to eq(2)
    end

    it "leaves groups at or under the limit untouched" do
      group = lane_view.result_for([], limit: 2).groups.last

      expect(group.items.map(&:name)).to eq(["S1"])
      expect(group.hidden_count).to be_nil
    end

    it "keeps the group's identity fields on a capped copy" do
      group = lane_view.result_for([], limit: 2).groups.first

      expect(group.checklist_id).to eq("cl-1")
      expect(group.name).to eq("Big @big")
    end

    it "caps tag-filtered groups the same way" do
      group = lane_view.result_for(["@big"], limit: 3).groups.first

      expect(group.items.map(&:name)).to eq(["B1", "B2", "B3"])
      expect(group.hidden_count).to eq(1)
    end

    it "does not mutate the underlying default view" do
      lane_view.result_for([], limit: 1)

      expect(lane_view.default_result.groups.first.items.size).to eq(4)
      expect(lane_view.default_result.groups.first.hidden_count).to be_nil
    end
  end

  describe "missing positions" do
    it "treats absent pos as 0 without blowing up" do
      checklist = api_checklist("checkItems" => [api_item]).tap do |cl|
        cl.delete("pos")
        cl["checkItems"].first.delete("pos")
      end
      stub_cards([card_with(id: "card-1", checklists: [checklist])])

      expect(lane_view.default_result.groups.first.items.map(&:name)).to eq(["Item One"])
    end
  end
end
