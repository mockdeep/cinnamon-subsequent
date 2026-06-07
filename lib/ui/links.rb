# frozen_string_literal: true

module UI
  # Single source of truth for "what counts as a link" in checklist text, shared
  # by ItemRow (which makes each URL clickable) and ChecklistView (whose header
  # button opens a grouping's URLs all at once). A link is any whitespace-
  # separated word carrying a real http(s) scheme, so loose lookalikes like
  # "httpd" never get linkified or handed to the browser launcher.
  module Links
    module_function

    def url?(word) = word.start_with?("http://", "https://")

    def in_text(text) = (text || "").split.select { |word| url?(word) }
  end
end
