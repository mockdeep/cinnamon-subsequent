# frozen_string_literal: true

# Builds the sidebar's view model from one lane's cards, fetched (with their
# checklists nested) in a single request.
#
# Returns a LaneView carrying two things derived from the same payload: the
# default view (the first card's incomplete checklists, exactly as the sidebar
# has always shown) and a lane-wide tag index, so the UI can switch between the
# default and any tag selection in memory without refetching.
#
# Tags are words beginning with "@" in a *checklist* name; an item inherits its
# checklist's tags. The tag index maps each tag to the flat list of incomplete
# items, across every card in the lane, whose checklist carries that tag.
class BoardFetch
  Result = Struct.new(:card_name, :groups, :empty_reason, keyword_init: true)
  Group  = Struct.new(:checklist_id, :name, :items, keyword_init: true)
  Item   = Struct.new(:id, :card_id, :checklist_id, :name, :state, keyword_init: true)
  Tag    = Struct.new(:name, :item_count, keyword_init: true)

  # The default first-card view plus the lane's tag index. `result_for` turns a
  # set of selected tag names into the Result to render: the default view when
  # nothing is selected, otherwise one group (heading + flat item list) per
  # selected tag, in name order. Unknown tag names are ignored, so a selection
  # carried across a refresh quietly drops tags that no longer exist.
  LaneView = Struct.new(:default_result, :tags, :items_by_tag, keyword_init: true) do
    def result_for(selected)
      names = Array(selected).select { |name| items_by_tag.key?(name) }.uniq.sort
      return default_result if names.empty?

      groups = names.map do |name|
        Group.new(checklist_id: nil, name: name, items: items_by_tag[name])
      end
      Result.new(card_name: nil, groups: groups, empty_reason: nil)
    end
  end

  def initialize(client, config)
    @client = client
    @config = config
  end

  def call
    return empty_view("No lane selected yet.") if blank?(@config.lane_id)

    cards = @client.cards_with_checklists(@config.lane_id)
    return empty_view("This lane has no cards.") if cards.empty?

    index = build_index(cards)
    LaneView.new(
      default_result: default_result(cards),
      tags: tags_from(index),
      items_by_tag: index,
    )
  end

  private

  # The first card's incomplete checklists - the sidebar's default view. When
  # that card is done we still return a LaneView (the lane's other cards may
  # carry tags), so the tag bar stays populated alongside the caught-up message.
  def default_result(cards)
    card = cards.first
    groups = build_groups(card["id"], card.fetch("checklists", []))
    if groups.empty?
      Result.new(card_name: card["name"], groups: [], empty_reason: "Nothing left — all caught up.")
    else
      Result.new(card_name: card["name"], groups: groups, empty_reason: nil)
    end
  end

  # Checklists in board order, incomplete items only, fully-complete lists dropped.
  def build_groups(card_id, checklists)
    in_order(checklists)
      .map { |cl| Group.new(checklist_id: cl["id"], name: cl["name"], items: incomplete_items(card_id, cl)) }
      .reject { |g| g.items.empty? }
  end

  # tag name => incomplete items, across every card, whose checklist has the tag.
  def build_index(cards)
    index = {}
    cards.each do |card|
      in_order(card.fetch("checklists", [])).each do |cl|
        tags = tag_names(cl["name"])
        next if tags.empty?

        items = incomplete_items(card["id"], cl)
        next if items.empty?

        tags.each { |tag| (index[tag] ||= []).concat(items) }
      end
    end
    index
  end

  def tags_from(index)
    index.keys.sort.map { |name| Tag.new(name: name, item_count: index[name].size) }
  end

  def tag_names(name)
    (name || "").split.select { |word| word.start_with?("@") }
  end

  def in_order(checklists)
    checklists.sort_by { |cl| cl["pos"] || 0 }
  end

  def incomplete_items(card_id, checklist)
    checklist.fetch("checkItems", [])
             .select { |i| i["state"] == "incomplete" }
             .sort_by { |i| i["pos"] || 0 }
             .map do |i|
               Item.new(id: i["id"], card_id: card_id, checklist_id: checklist["id"],
                        name: i["name"], state: i["state"])
             end
  end

  def empty_view(reason)
    LaneView.new(
      default_result: Result.new(card_name: nil, groups: [], empty_reason: reason),
      tags: [],
      items_by_tag: {},
    )
  end

  def blank?(value) = value.nil? || (value.respond_to?(:empty?) && value.empty?)
end
