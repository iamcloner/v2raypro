class SubscriptionItem {
  final String id;
  String name;
  String url;
  DateTime? lastUpdated;
  int nodeCount;

  SubscriptionItem({
    required this.id,
    required this.name,
    required this.url,
    this.lastUpdated,
    this.nodeCount = 0,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "url": url,
    "last_updated": lastUpdated?.toIso8601String(),
    "node_count": nodeCount,
  };

  factory SubscriptionItem.fromJson(Map<String, dynamic> json) {
    return SubscriptionItem(
      id: json["id"] ?? "",
      name: json["name"] ?? "Subscription",
      url: json["url"] ?? "",
      lastUpdated: json["last_updated"] != null
          ? DateTime.tryParse(json["last_updated"])
          : null,
      nodeCount: (json["node_count"] as num?)?.toInt() ?? 0,
    );
  }

  SubscriptionItem copyWith({
    String? name,
    String? url,
    DateTime? lastUpdated,
    int? nodeCount,
  }) {
    return SubscriptionItem(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      nodeCount: nodeCount ?? this.nodeCount,
    );
  }
}
