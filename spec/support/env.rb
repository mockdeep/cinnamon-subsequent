# frozen_string_literal: true

# Run a block with an environment variable set to a value, restoring it after
# (a nil value unsets it for the duration).
module EnvHelpers
  def with_env(key, value)
    original = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    ENV[key] = original
  end
end

RSpec.configure do |config|
  config.include(EnvHelpers)
end
