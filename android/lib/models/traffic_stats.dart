class TrafficStats {
  final int downlinkBytes;
  final int uplinkBytes;
  const TrafficStats({this.downlinkBytes = 0, this.uplinkBytes = 0});

  int get totalBytes => downlinkBytes + uplinkBytes;
  String get formattedDownlink => formatBytes(downlinkBytes);
  String get formattedUplink => formatBytes(uplinkBytes);
  String get formattedTotal => formatBytes(totalBytes);

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0.0 B';
    if (bytes < 1024) return '$bytes.0 B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}