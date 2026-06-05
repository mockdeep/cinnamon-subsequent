# frozen_string_literal: true

RSpec.describe TrelloClient do
  subject(:client) { trello_client }

  describe "#boards" do
    let(:url) { api_url("/members/me/boards", fields: "name", filter: "open") }

    it "returns the open boards" do
      stub_request(:get, url).to_return(body: [api_board].to_json)

      expect(client.boards).to eq([api_board])
    end

    it "raises a TrelloClient::Error when the request fails" do
      stub_request(:get, url).to_return(status: 500)

      expect { client.boards }
        .to raise_error(TrelloClient::Error, /500/)
    end
  end

  describe "#lists" do
    it "returns the open lists for a board" do
      url = api_url("/boards/b1/lists", fields: "name", filter: "open")
      stub_request(:get, url).to_return(body: [api_list].to_json)

      expect(client.lists("b1")).to eq([api_list])
    end
  end

  describe "#cards" do
    it "returns the open cards for a list" do
      url = api_url("/lists/l1/cards", fields: "name", filter: "open")
      stub_request(:get, url).to_return(body: [api_card].to_json)

      expect(client.cards("l1")).to eq([api_card])
    end
  end

  describe "#cards_with_checklists" do
    it "returns the open cards with their checklists and items nested" do
      url = api_url(
        "/lists/l1/cards",
        fields: "name",
        filter: "open",
        checklists: "all",
        checklist_fields: "name,pos",
        checkItems: "all",
        checkItem_fields: "name,state,pos",
      )
      card = api_card("checklists" => [api_checklist("checkItems" => [api_item])])
      stub_request(:get, url).to_return(body: [card].to_json)

      expect(client.cards_with_checklists("l1")).to eq([card])
    end
  end

  describe "#checklists" do
    it "returns the checklists for a card with their items" do
      url = api_url(
        "/cards/c1/checklists",
        fields: "name,pos",
        checkItems: "all",
        checkItem_fields: "name,state,pos",
      )
      checklist = api_checklist("checkItems" => [api_item])
      stub_request(:get, url).to_return(body: [checklist].to_json)

      expect(client.checklists("c1")).to eq([checklist])
    end
  end

  describe "#set_check_item_state" do
    it "PUTs state=complete and returns the updated item" do
      url = api_url("/cards/c1/checkItem/i1", state: "complete")
      stub_request(:put, url).to_return(body: api_item("state" => "complete").to_json)

      result = client.set_check_item_state("c1", "i1", true)

      expect(result).to eq(api_item("state" => "complete"))
    end

    it "PUTs state=incomplete when uncompleting" do
      url = api_url("/cards/c1/checkItem/i1", state: "incomplete")
      stub = stub_request(:put, url).to_return(body: api_item.to_json)

      client.set_check_item_state("c1", "i1", false)

      expect(stub).to have_been_requested
    end

    it "raises a TrelloClient::Error when the request fails" do
      url = api_url("/cards/c1/checkItem/i1", state: "complete")
      stub_request(:put, url).to_return(status: 400)

      expect { client.set_check_item_state("c1", "i1", true) }
        .to raise_error(TrelloClient::Error, /400/)
    end
  end
end
