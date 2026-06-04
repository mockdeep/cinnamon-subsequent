# frozen_string_literal: true

RSpec.describe BoardFetch do
  subject(:result) { described_class.new(client, config).call }

  let(:client) { instance_double(TrelloClient) }
  let(:config) { instance_double(Config, lane_id: "lane-1") }

  describe "empty states" do
    it "reports when no lane is selected (nil)" do
      allow(config).to receive(:lane_id).and_return(nil)

      expect(result.empty_reason).to eq("No lane selected yet.")
      expect(result.groups).to be_empty
    end

    it "reports when no lane is selected (blank string)" do
      allow(config).to receive(:lane_id).and_return("")

      expect(result.empty_reason).to eq("No lane selected yet.")
    end

    it "reports when the lane has no cards" do
      allow(client).to receive(:cards).with("lane-1").and_return([])

      expect(result.empty_reason).to eq("This lane has no cards.")
      expect(result.groups).to be_empty
    end

    it "reports all-caught-up, naming the card, when nothing is incomplete" do
      allow(client).to receive(:cards).and_return([api_card("name" => "My Card")])
      allow(client).to receive(:checklists)
        .and_return([api_checklist("checkItems" => [api_item("state" => "complete")])])

      expect(result.empty_reason).to eq("Nothing left — all caught up.")
      expect(result.card_name).to eq("My Card")
      expect(result.groups).to be_empty
    end
  end

  describe "building groups" do
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

    before do
      allow(client).to receive(:cards).with("lane-1")
        .and_return([api_card("id" => "card-1", "name" => "My Card"), api_card("id" => "card-2")])
      allow(client).to receive(:checklists).with("card-1").and_return(checklists)
    end

    it "uses the first card only" do
      result

      expect(client).to have_received(:checklists).with("card-1")
      expect(result.card_name).to eq("My Card")
    end

    it "orders checklists by pos" do
      expect(result.groups.map(&:name)).to eq(["First", "Second"])
    end

    it "keeps only incomplete items, ordered by pos" do
      first = result.groups.first

      expect(first.items.map(&:name)).to eq(["A1", "A2"])
    end

    it "maps each item with its card and checklist ids" do
      item = result.groups.first.items.first

      expect(item).to have_attributes(
        id: "a1",
        card_id: "card-1",
        checklist_id: "cl-1",
        name: "A1",
        state: "incomplete",
      )
    end

    it "drops checklists left with no incomplete items" do
      allow(client).to receive(:checklists).with("card-1").and_return(
        [api_checklist("checkItems" => [api_item("state" => "complete")])],
      )

      expect(result.groups).to be_empty
    end
  end

  describe "missing positions" do
    it "treats absent pos as 0 without blowing up" do
      allow(client).to receive(:cards).and_return([api_card("id" => "card-1")])
      checklist = api_checklist("checkItems" => [api_item]).tap do |cl|
        cl.delete("pos")
        cl["checkItems"].first.delete("pos")
      end
      allow(client).to receive(:checklists).and_return([checklist])

      expect(result.groups.first.items.map(&:name)).to eq(["Item One"])
    end
  end
end
