# frozen_string_literal: true

require "x11/strut"

RSpec.describe X11::Strut do
  # Stub the Xlib FFI boundary so we assert the property *logic* (which atoms,
  # which arrays) without touching a real X server.
  let(:changes) { [] }
  let(:lib_double) do
    Module.new do
      def self.calls = (@calls ||= [])
      def self.XOpenDisplay(_) = :display
      def self.XInternAtom(_display, name, _only) = name # echo the atom name
      def self.XChangeProperty(*args) = calls << args
      def self.XFlush(_) = nil
    end
  end

  before do
    described_class.instance_variable_set(:@display, nil)
    stub_const("#{described_class}::Lib", lib_double)
  end

  # Drop the display memoized against the stubbed Lib so a real Xlib call in
  # another spec re-opens a real one.
  after { described_class.instance_variable_set(:@display, nil) }

  def change_for(prop_name)
    lib_double.calls.find { |args| args[2] == prop_name }
  end

  # XChangeProperty(display, xid, atom, type, format, mode, data, nelements)
  def data_for(prop_name) = change_for(prop_name)[6].unpack("l!*")

  describe ".apply_right" do
    before do
      described_class.apply_right(42, width: 10, start_y: 5, end_y: 100)
    end

    it "sets _NET_WM_STRUT_PARTIAL with the right-edge span" do
      expect(data_for("_NET_WM_STRUT_PARTIAL"))
        .to eq([0, 10, 0, 0, 0, 0, 5, 100, 0, 0, 0, 0])
    end

    it "sets _NET_WM_STRUT with just the four edge reservations" do
      expect(data_for("_NET_WM_STRUT")).to eq([0, 10, 0, 0])
    end

    it "writes both properties to the given window as CARDINAL/format-32" do
      partial = change_for("_NET_WM_STRUT_PARTIAL")
      display, xid, _atom, type, format, mode, _data, nelements = partial

      expect([display, xid]).to eq([:display, 42])
      expect([type, format, mode]).to eq([6, 32, 0]) # XA_CARDINAL, 32, REPLACE
      expect(nelements).to eq(12)
    end
  end
end
