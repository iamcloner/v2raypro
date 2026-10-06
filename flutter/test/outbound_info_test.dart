import "package:flutter_test/flutter_test.dart";
import "package:v2raypro/models/outbound_info.dart";

void main() {
  group("OutboundInfo Model Tests", () {
    test("flagEmoji converts 2-letter ISO country codes correctly", () {
      const de = OutboundInfo(countryCode: "DE");
      expect(de.flagEmoji, "🇩🇪");

      const us = OutboundInfo(countryCode: "US");
      expect(us.flagEmoji, "🇺🇸");

      const fi = OutboundInfo(countryCode: "FI");
      expect(fi.flagEmoji, "🇫🇮");

      const ir = OutboundInfo(countryCode: "IR");
      expect(ir.flagEmoji, "🇮🇷");

      const invalid = OutboundInfo(countryCode: "USA");
      expect(invalid.flagEmoji, "🌐");

      const empty = OutboundInfo();
      expect(empty.flagEmoji, "🌐");
    });

    test("copyWith updates fields properly", () {
      const info = OutboundInfo(ipv4: "1.1.1.1", country: "Australia");
      final updated = info.copyWith(ipv6: "2606:4700::", isLoading: true);

      expect(updated.ipv4, "1.1.1.1");
      expect(updated.country, "Australia");
      expect(updated.ipv6, "2606:4700::");
      expect(updated.isLoading, true);
    });
  });
}
