class OutboundInfo {
  final String? ipv4;
  final String? ipv6;
  final String? country;
  final String? countryCode;
  final String? city;
  final String? isp;
  final bool isLoading;
  final String? error;

  const OutboundInfo({
    this.ipv4,
    this.ipv6,
    this.country,
    this.countryCode,
    this.city,
    this.isp,
    this.isLoading = false,
    this.error,
  });

  String get flagEmoji {
    if (countryCode == null || countryCode!.length != 2) return "🌐";
    final code = countryCode!.toUpperCase();
    final first = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  OutboundInfo copyWith({
    String? ipv4,
    String? ipv6,
    String? country,
    String? countryCode,
    String? city,
    String? isp,
    bool? isLoading,
    String? error,
  }) {
    return OutboundInfo(
      ipv4: ipv4 ?? this.ipv4,
      ipv6: ipv6 ?? this.ipv6,
      country: country ?? this.country,
      countryCode: countryCode ?? this.countryCode,
      city: city ?? this.city,
      isp: isp ?? this.isp,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}
