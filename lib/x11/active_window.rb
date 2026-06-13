# frozen_string_literal: true

require "fiddle"
require "fiddle/import"

module X11
  # Reads _NET_ACTIVE_WINDOW off the root window via Xlib, so a standalone
  # process (we're not inside the Cinnamon shell) can tell which window is
  # focused. The sidebar uses it to ring the session dot whose terminal is
  # active. Like X11::Strut, this calls Xlib through fiddle because the gdk3
  # binding doesn't expose gdk_property_get.
  module ActiveWindow
    module Lib
      extend Fiddle::Importer

      dlload "libX11.so.6"
      extern "void* XOpenDisplay(char*)"
      extern "unsigned long XInternAtom(void*, char*, int)"
      extern "unsigned long XDefaultRootWindow(void*)"
      extern "int XGetWindowProperty(void*, unsigned long, unsigned long, " \
             "long, long, int, unsigned long, " \
             "void*, void*, void*, void*, void*)"
      extern "int XFree(void*)"
    end

    SUCCESS = 0
    ANY_PROPERTY_TYPE = 0

    class << self
      # The XID of the active window per _NET_ACTIVE_WINDOW, or nil when it's
      # unset (no active window, or a WM that doesn't publish the property).
      def current
        property = Lib.XInternAtom(display, "_NET_ACTIVE_WINDOW", 0)
        root = Lib.XDefaultRootWindow(display)

        actual_type   = pointer(Fiddle::SIZEOF_LONG)
        actual_format = pointer(Fiddle::SIZEOF_INT)
        nitems        = pointer(Fiddle::SIZEOF_LONG)
        bytes_after   = pointer(Fiddle::SIZEOF_LONG)
        prop          = pointer(Fiddle::SIZEOF_VOIDP)

        status = Lib.XGetWindowProperty(
          display,
          root,
          property,
          0,
          1,
          0,
          ANY_PROPERTY_TYPE,
          actual_type,
          actual_format,
          nitems,
          bytes_after,
          prop,
        )
        return unless status == SUCCESS

        decode(nitems, prop)
      end

      private

      # nitems holds the element count; prop dereferences to the property data,
      # a single CARD32 (the XID) stored — per Xlib's format-32 convention — as
      # a native long. XFree releases the buffer Xlib allocated.
      def decode(nitems, prop)
        return if read_ulong(nitems).zero?

        data = prop.ptr
        return if data.null?

        xid = read_ulong(data)
        Lib.XFree(data)
        xid.zero? ? nil : xid
      end

      def read_ulong(ptr) = ptr[0, Fiddle::SIZEOF_LONG].unpack1("L!")

      def pointer(size) = Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE)

      def display
        @display ||= Lib.XOpenDisplay(nil)
      end
    end
  end
end
