# frozen_string_literal: true

require "fiddle"
require "x11/active_window"

RSpec.describe X11::ActiveWindow do
  # Stub the Xlib FFI boundary so we exercise the property-decoding logic with
  # no real X server. XGetWindowProperty writes through the out-pointers our code
  # allocated, mimicking Xlib filling in the count and a pointer to the data.
  let(:lib_double) do
    Module.new do
      class << self
        attr_accessor :nitems, :xid

        def freed = (@freed ||= [])

        def XOpenDisplay(_) = :display
        def XInternAtom(_display, name, _only) = name
        def XDefaultRootWindow(_display) = 1

        def XGetWindowProperty(*args)
          nitems_ptr = args[9]
          prop_ptr = args[11]
          nitems_ptr[0, Fiddle::SIZEOF_LONG] = [nitems].pack("L!")
          if nitems.positive?
            @data = Fiddle::Pointer.malloc(Fiddle::SIZEOF_LONG, Fiddle::RUBY_FREE)
            @data[0, Fiddle::SIZEOF_LONG] = [xid].pack("L!")
            prop_ptr[0, Fiddle::SIZEOF_VOIDP] = [@data.to_i].pack("J")
          else
            prop_ptr[0, Fiddle::SIZEOF_VOIDP] = [0].pack("J")
          end
          0
        end

        def XFree(ptr) = freed << ptr.to_i
      end
    end
  end

  before do
    described_class.instance_variable_set(:@display, nil)
    lib_double.nitems = 1
    lib_double.xid = 0x1a00007
    stub_const("#{described_class}::Lib", lib_double)
  end

  # Drop the display memoized against the stub so a real Xlib call elsewhere
  # re-opens a real one.
  after { described_class.instance_variable_set(:@display, nil) }

  describe ".current" do
    it "returns the XID decoded from _NET_ACTIVE_WINDOW" do
      expect(described_class.current).to eq(0x1a00007)
    end

    it "frees the property buffer Xlib returned" do
      described_class.current

      expect(lib_double.freed).not_to be_empty
    end

    it "returns nil when the property is unset (no elements)" do
      lib_double.nitems = 0

      expect(described_class.current).to be_nil
    end

    it "returns nil when the active window id is zero" do
      lib_double.xid = 0

      expect(described_class.current).to be_nil
    end
  end
end
