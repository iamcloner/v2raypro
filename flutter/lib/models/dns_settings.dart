class DnsPreset {
  final String id;
  final String name;
  final String nameFa;
  final List<String> servers;

  const DnsPreset({
    required this.id,
    required this.name,
    required this.nameFa,
    required this.servers,
  });
}

class DnsSettings {
  final String presetId;
  final List<String> servers;

  const DnsSettings({
    this.presetId = "cloudflare",
    this.servers = const [
      "1.1.1.1",
      "1.0.0.1",
      "https://1.1.1.1/dns-query",
    ],
  });

  static const List<DnsPreset> presets = [
    DnsPreset(
      id: "cloudflare",
      name: "Cloudflare (1.1.1.1)",
      nameFa: "کلودفلر (1.1.1.1)",
      servers: [
        "1.1.1.1",
        "1.0.0.1",
        "https://1.1.1.1/dns-query",
      ],
    ),
    DnsPreset(
      id: "google",
      name: "Google (8.8.8.8)",
      nameFa: "گوگل (8.8.8.8)",
      servers: [
        "8.8.8.8",
        "8.8.4.4",
        "https://dns.google/dns-query",
      ],
    ),
    DnsPreset(
      id: "quad9",
      name: "Quad9 (9.9.9.9)",
      nameFa: "کوادناین (9.9.9.9)",
      servers: [
        "9.9.9.9",
        "149.112.112.112",
        "https://dns.quad9.net/dns-query",
      ],
    ),
    DnsPreset(
      id: "shecan",
      name: "Shecan (تحریم‌شکن شکن)",
      nameFa: "شکن (ضد تحریم)",
      servers: [
        "178.22.122.100",
        "185.51.200.2",
      ],
    ),
    DnsPreset(
      id: "electro",
      name: "Electro (تحریم‌شکن الکترو)",
      nameFa: "الکترو (ضد تحریم)",
      servers: [
        "78.157.42.100",
        "78.157.42.101",
      ],
    ),
    DnsPreset(
      id: "custom",
      name: "Custom DNS",
      nameFa: "دی‌ان‌اس سفارشی",
      servers: [],
    ),
  ];

  Map<String, dynamic> toJson() => {
    "preset_id": presetId,
    "servers": servers,
  };

  factory DnsSettings.fromJson(Map<String, dynamic> json) {
    final sList = (json["servers"] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [
          "1.1.1.1",
          "1.0.0.1",
          "https://1.1.1.1/dns-query",
        ];
    return DnsSettings(
      presetId: json["preset_id"] as String? ?? "cloudflare",
      servers: sList.isNotEmpty ? sList : const ["1.1.1.1", "1.0.0.1"],
    );
  }

  DnsSettings copyWith({
    String? presetId,
    List<String>? servers,
  }) {
    return DnsSettings(
      presetId: presetId ?? this.presetId,
      servers: servers ?? this.servers,
    );
  }
}
