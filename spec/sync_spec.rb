# frozen_string_literal: true

RSpec.describe Sync do
  # Results come back via GLib::Idle.add, so pump the main loop until the
  # condition holds (or we hit the timeout guard, which fails the wait).
  def pump_until(timeout_ms: 2000)
    loop = GLib::MainLoop.new
    elapsed = 0
    GLib::Timeout.add(10) do
      elapsed += 10
      keep_going = !yield && elapsed < timeout_ms
      loop.quit unless keep_going
      keep_going
    end
    loop.run
  end

  it "delivers the work's result to on_success" do
    result = nil

    described_class.run(-> { 6 * 7 }, on_success: ->(value) { result = value })
    pump_until { !result.nil? }

    expect(result).to eq(42)
  end

  it "runs work off the main thread but the callback on it" do
    main = Thread.current
    work_thread = nil
    callback_thread = nil

    described_class.run(
      -> { work_thread = Thread.current },
      on_success: ->(_) { callback_thread = Thread.current },
    )
    pump_until { callback_thread }

    expect(work_thread).not_to eq(main)
    expect(callback_thread).to eq(main)
  end

  it "routes a StandardError raised by work to on_error" do
    captured = nil

    described_class.run(
      -> { raise StandardError, "boom" },
      on_success: ->(_) { raise StandardError, "nope" },
      on_error: ->(error) { captured = error },
    )
    pump_until { captured }

    expect(captured).to be_a(StandardError).and(have_attributes(message: "boom"))
  end

  it "warns via the default handler when on_error is omitted" do
    messages = []
    allow(described_class).to receive(:warn) { |message| messages << message }

    described_class.run(
      -> { raise StandardError, "boom" },
      on_success: lambda { |_|
      },
    )
    pump_until { messages.any? }

    expect(messages.first).to match(/Sync error: boom/)
  end
end
