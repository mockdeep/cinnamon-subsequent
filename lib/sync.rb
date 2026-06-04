# frozen_string_literal: true

require "gtk3"

# Runs a blocking unit of work (a Trello call) on a background thread, then
# delivers the result back on the GTK main thread via GLib::Idle.add. This is
# the ONLY safe way to touch widgets from work that started off-thread: the
# `work` proc must not call GTK; the `on_success`/`on_error` callbacks run on
# the main thread and may.
module Sync
  module_function

  def run(work, on_success:, on_error: nil)
    Thread.new do
      begin
        result = work.call
        GLib::Idle.add { on_success.call(result); false }
      rescue StandardError => e
        handler = on_error || ->(err) { warn "Sync error: #{err.message}" }
        GLib::Idle.add { handler.call(e); false }
      end
    end
  end
end
