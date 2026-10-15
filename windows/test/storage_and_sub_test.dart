import "package:flutter_test/flutter_test.dart";
import "../lib/models/subscription_item.dart";
import "../lib/utils/config_parser.dart";

void main() {
  test("SubscriptionItem serialization works", () {
    final sub = SubscriptionItem(
      id: "sub-1",
      name: "My Sub",
      url: "https://example.com/sub",
      lastUpdated: DateTime(2026, 10, 6, 10, 0),
      nodeCount: 5,
    );

    final json = sub.toJson();
    final restored = SubscriptionItem.fromJson(json);

    expect(restored.id, "sub-1");
    expect(restored.name, "My Sub");
    expect(restored.url, "https://example.com/sub");
    expect(restored.nodeCount, 5);
  });

  test("ConfigParser parses multi-line subscription content", () {
    final subContent = """
vless://a6be2b03-b846-49c8-ad62-79b1a773b960@8.6.112.246:2053?encryption=none&security=tls&sni=gaia.payamnews.com&fp=chrome&alpn=h2%2Chttp%2F1.1&type=xhttp&host=gaia.payamnews.com&path=%2Fpkgs%2F&mode=auto#Node1
trojan://password123@104.16.1.1:443?security=tls&sni=example.com#Node2
""";

    final nodes = ConfigParser.parseBatch(subContent);
    expect(nodes.length, 2);
    expect(nodes[0].name, "Node1");
    expect(nodes[1].name, "Node2");
    expect(nodes[0].id != nodes[1].id, true);
  });

  test("ConfigParser batch parse generates all unique IDs", () {
    final urls = List.generate(
      10,
      (i) => "vless://uuid$i@1.1.1.$i:443?type=tcp#Node$i",
    ).join("\n");

    final nodes = ConfigParser.parseBatch(urls);
    expect(nodes.length, 10);
    final ids = nodes.map((n) => n.id).toSet();
    expect(ids.length, 10); // All 10 must have strictly unique IDs
  });
}
