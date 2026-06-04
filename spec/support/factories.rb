# frozen_string_literal: true

# Builders for the JSON-shaped hashes the Trello API returns. Keys are strings,
# matching parsed responses, since that's what TrelloClient and BoardFetch read.
module Factories
  def api_board(overrides = {})
    { "id" => "board-1", "name" => "Board One" }.merge(stringify(overrides))
  end

  def api_list(overrides = {})
    { "id" => "list-1", "name" => "List One" }.merge(stringify(overrides))
  end

  def api_card(overrides = {})
    { "id" => "card-1", "name" => "Card One" }.merge(stringify(overrides))
  end

  def api_checklist(overrides = {})
    {
      "id" => "checklist-1",
      "name" => "Checklist",
      "pos" => 1,
      "checkItems" => [],
    }.merge(stringify(overrides))
  end

  def api_item(overrides = {})
    {
      "id" => "item-1",
      "name" => "Item One",
      "state" => "incomplete",
      "pos" => 1,
    }.merge(stringify(overrides))
  end

  private

  def stringify(hash)
    hash.transform_keys(&:to_s)
  end
end

RSpec.configure do |config|
  config.include(Factories)
end
