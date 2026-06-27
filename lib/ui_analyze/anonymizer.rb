# frozen_string_literal: true

module UiAnalyze
  # Replaces identifying values with stable, deterministic placeholders.
  # Each unique value gets the same placeholder within a session.
  class Anonymizer
    MAC_RE    = /\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/
    UUID_RE   = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i
    SERIAL_RE = /\b[A-Z0-9]{10,20}\b/

    SERIAL_BASES = %w[aabbccddeeff bbaaccddeefd ccbbddaaeeff].freeze
    MAC_BASES    = %w[aa:bb:cc:dd:ee:ff bb:aa:cc:dd:ee:fd cc:bb:dd:aa:ee:ff].freeze

    def initialize
      @counters = Hash.new(0)
      @map = {}
    end

    def serial(v)  = redact(v, :serial)
    def mac(v)     = redact(v, :mac)
    def uuid(v)    = redact(v, "UUID")
    def qr_id(v)   = redact(v, "QRID")
    def anon_id(v) = redact(v, "ANONID")
    def hash_id(v) = redact(v, "HASHID")
    def bom(v)     = redact(v, "BOM")
    def hostname(v) = redact(v, "HOST")

    # Replace MAC addresses, UUIDs, and long uppercase serials in an arbitrary string.
    def scrub(v)
      return v unless v
      v = v.gsub(MAC_RE)    { redact($&, :mac) }
      v = v.gsub(UUID_RE)   { redact($&, "UUID") }
      v = v.gsub(SERIAL_RE) { redact($&, :serial) }
      v
    end

    private

    def redact(v, prefix)
      return v unless v
      @map[v] ||= begin
        @counters[prefix] += 1
        n = @counters[prefix]
        case prefix
        when :serial then SERIAL_BASES[n - 1] || "aabbccddeeff#{n}"
        when :mac    then MAC_BASES[n - 1]    || "aa:bb:cc:dd:ee:#{n.to_s(16).rjust(2, "0")}"
        else n == 1 ? "<#{prefix}>" : "<#{prefix}#{n}>"
        end
      end
    end
  end
end
