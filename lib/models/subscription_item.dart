class SubscriptionItem {
  final String id;
  String name;
  String url;
  DateTime? lastUpdated;
  int nodeCount;
  bool autoUpdate;
  int? uploadBytes;
  int? downloadBytes;
  int? totalBytes;
  DateTime? expireDate;

  SubscriptionItem({
    required this.id,
    required this.name,
    required this.url,
    this.lastUpdated,
    this.nodeCount = 0,
    this.autoUpdate = false,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expireDate,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "url": url,
    "last_updated": lastUpdated?.toIso8601String(),
    "node_count": nodeCount,
    "auto_update": autoUpdate,
    "upload_bytes": uploadBytes,
    "download_bytes": downloadBytes,
    "total_bytes": totalBytes,
    "expire_date": expireDate?.toIso8601String(),
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
      autoUpdate: json["auto_update"] == true,
      uploadBytes: (json["upload_bytes"] as num?)?.toInt(),
      downloadBytes: (json["download_bytes"] as num?)?.toInt(),
      totalBytes: (json["total_bytes"] as num?)?.toInt(),
      expireDate: json["expire_date"] != null
          ? DateTime.tryParse(json["expire_date"])
          : null,
    );
  }

  SubscriptionItem copyWith({
    String? name,
    String? url,
    DateTime? lastUpdated,
    int? nodeCount,
    bool? autoUpdate,
    int? uploadBytes,
    int? downloadBytes,
    int? totalBytes,
    DateTime? expireDate,
  }) {
    return SubscriptionItem(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      nodeCount: nodeCount ?? this.nodeCount,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      uploadBytes: uploadBytes ?? this.uploadBytes,
      downloadBytes: downloadBytes ?? this.downloadBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      expireDate: expireDate ?? this.expireDate,
    );
  }

  String? get formattedRemainingTraffic {
    if (totalBytes != null && totalBytes! > 0) {
      final used = (uploadBytes ?? 0) + (downloadBytes ?? 0);
      final remaining = totalBytes! - used;
      final remainingGb = remaining / (1024 * 1024 * 1024);
      final totalGb = totalBytes! / (1024 * 1024 * 1024);
      if (remainingGb >= 0) {
        return "${remainingGb.toStringAsFixed(1)} GB / ${totalGb.toStringAsFixed(0)} GB";
      } else {
        return "0 GB / ${totalGb.toStringAsFixed(0)} GB";
      }
    }
    return null;
  }

  String? get formattedRemainingTime {
    if (expireDate != null) {
      final diff = expireDate!.difference(DateTime.now());
      if (diff.isNegative) {
        return "Expired";
      } else if (diff.inDays > 0) {
        return "${diff.inDays} days left";
      } else if (diff.inHours > 0) {
        return "${diff.inHours} hours left";
      } else {
        return "${diff.inMinutes} mins left";
      }
    }
    return null;
  }
}
