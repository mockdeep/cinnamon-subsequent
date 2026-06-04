# frozen_string_literal: true

module TrelloHelpers
  TEST_KEY = "test-key"
  TEST_TOKEN = "test-token"

  def trello_client
    TrelloClient.new(key: TEST_KEY, token: TEST_TOKEN)
  end

  # The full request URL the client would hit for `path` + `params`, including
  # the key/token it always appends — so a WebMock stub matches it exactly.
  def api_url(path, **params)
    uri = URI("#{TrelloClient::BASE}#{path}")
    uri.query =
      URI.encode_www_form(params.merge(key: TEST_KEY, token: TEST_TOKEN))
    uri.to_s
  end
end

RSpec.configure do |config|
  config.include(TrelloHelpers)
end
