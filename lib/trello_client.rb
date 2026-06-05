# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Thin read-only wrapper over the Trello REST API (stdlib only).
# Auth is the standard key + token pair, passed as query params.
# Write support (checking/unchecking items) is added in a later step.
class TrelloClient
  BASE = "https://api.trello.com/1"

  class Error < StandardError; end

  def initialize(key:, token:)
    @key = key
    @token = token
  end

  # Open boards the user is a member of: [{id, name}, ...]
  def boards
    get("/members/me/boards", fields: "name", filter: "open")
  end

  # Lists ("lanes") on a board, in board order: [{id, name}, ...]
  def lists(board_id)
    get("/boards/#{board_id}/lists", fields: "name", filter: "open")
  end

  # Open cards in a list, in order: [{id, name}, ...]
  def cards(list_id)
    get("/lists/#{list_id}/cards", fields: "name", filter: "open")
  end

  # Open cards in a list, each with its checklists and their check-items nested,
  # in a single request - so tag filtering can span every card in the lane
  # without a per-card fan-out:
  #   [{id, name, checklists: [{id, name, pos, checkItems: [...]}, ...]}, ...]
  def cards_with_checklists(list_id)
    get("/lists/#{list_id}/cards",
        fields: "name",
        filter: "open",
        checklists: "all",
        checklist_fields: "name,pos",
        checkItems: "all",
        checkItem_fields: "name,state,pos")
  end

  # Checklists on a card, each with its check-items and their state:
  # [{id, name, checkItems: [{id, name, state, pos}, ...]}, ...]
  def checklists(card_id)
    get("/cards/#{card_id}/checklists",
        fields: "name,pos",
        checkItems: "all",
        checkItem_fields: "name,state,pos")
  end

  # Mark a checklist item complete/incomplete. Returns the updated item.
  def set_check_item_state(card_id, check_item_id, complete)
    put("/cards/#{card_id}/checkItem/#{check_item_id}",
        state: complete ? "complete" : "incomplete")
  end

  private

  def put(path, params = {})
    request(Net::HTTP::Put, path, params)
  end

  def get(path, params = {})
    request(Net::HTTP::Get, path, params)
  end

  def request(verb_class, path, params)
    uri = URI("#{BASE}#{path}")
    uri.query = URI.encode_www_form(params.merge(key: @key, token: @token))
    http_request = verb_class.new(uri.request_uri)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "Trello #{verb_class::METHOD} #{path} → " \
                   "#{response.code} #{response.message}: #{response.body}"
    end

    JSON.parse(response.body)
  end
end
