# frozen_string_literal: true

require "fiddle"
require "fiddle/import"

module X11
  # Sets _NET_WM_STRUT(_PARTIAL) directly via Xlib, since the gdk3 binding
  # doesn't expose gdk_property_change. The window manager reads these
  # properties to carve out screen space that maximized windows must avoid.
  module Strut
    module Lib
      extend Fiddle::Importer
      dlload "libX11.so.6"
      extern "void* XOpenDisplay(char*)"
      extern "unsigned long XInternAtom(void*, char*, int)"
      extern "int XChangeProperty(void*, unsigned long, unsigned long, unsigned long, int, int, void*, int)"
      extern "int XFlush(void*)"
    end

    XA_CARDINAL = 6
    PROP_MODE_REPLACE = 0
    FORMAT_32 = 32

    class << self
      # Reserve `width` px on the right edge, spanning y in [start_y, end_y].
      def apply_right(xid, width:, start_y:, end_y:)
        partial = [0, width, 0, 0,  0, 0,  start_y, end_y,  0, 0,  0, 0]
        strut   = [0, width, 0, 0]
        change(xid, "_NET_WM_STRUT_PARTIAL", partial)
        change(xid, "_NET_WM_STRUT", strut)
        Lib.XFlush(display)
      end

      private

      def display
        @display ||= Lib.XOpenDisplay(nil)
      end

      def atom(name)
        Lib.XInternAtom(display, name, 0)
      end

      def change(xid, prop_name, values)
        data = values.pack("l!*") # native long; Xlib expects long[] for format 32
        Lib.XChangeProperty(display, xid, atom(prop_name), XA_CARDINAL,
                            FORMAT_32, PROP_MODE_REPLACE, data, values.length)
      end
    end
  end
end
