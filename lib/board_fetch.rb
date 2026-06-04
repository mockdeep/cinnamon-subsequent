# frozen_string_literal: true

# Builds the sidebar's view model from Trello: the first card of the selected
# lane and its checklists, keeping only incomplete items, grouped by checklist.
#
# Returns a Result whose `groups` is empty when there's nothing to show; in that
# case `empty_reason` explains why (no lane, empty lane, no checklists, or all
# done) so the UI can render a friendly empty state instead of a blank panel.
class BoardFetch
  Result = Struct.new(:card_name, :groups, :empty_reason, keyword_init: true)
  Group  = Struct.new(:checklist_id, :name, :items, keyword_init: true)
  Item   = Struct.new(:id, :card_id, :checklist_id, :name, :state, keyword_init: true)

  def initialize(client, config)
    @client = client
    @config = config
  end

  def call
    return empty("No lane selected yet.") if blank?(@config.lane_id)

    cards = @client.cards(@config.lane_id)
    return empty("This lane has no cards.") if cards.empty?

    card = cards.first
    groups = build_groups(card["id"], @client.checklists(card["id"]))

    if groups.empty?
      empty("Nothing left — all caught up.", card_name: card["name"])
    else
      Result.new(card_name: card["name"], groups: groups, empty_reason: nil)
    end
  end

  private

  # Checklists in board order, incomplete items only, fully-complete lists dropped.
  def build_groups(card_id, checklists)
    checklists
      .sort_by { |cl| cl["pos"] || 0 }
      .map do |cl|
        items = cl.fetch("checkItems", [])
                  .select { |i| i["state"] == "incomplete" }
                  .sort_by { |i| i["pos"] || 0 }
                  .map do |i|
                    Item.new(id: i["id"], card_id: card_id, checklist_id: cl["id"],
                             name: i["name"], state: i["state"])
                  end
        Group.new(checklist_id: cl["id"], name: cl["name"], items: items)
      end
      .reject { |g| g.items.empty? }
  end

  def empty(reason, card_name: nil)
    Result.new(card_name: card_name, groups: [], empty_reason: reason)
  end

  def blank?(value) = value.nil? || (value.respond_to?(:empty?) && value.empty?)
end
