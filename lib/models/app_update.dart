class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseName,
    required this.releaseUrl,
    required this.assetName,
    required this.downloadUrl,
    required this.size,
    required this.publishedAt,
    required this.body,
  });

  final String version;
  final String tagName;
  final String releaseName;
  final String releaseUrl;
  final String assetName;
  final String downloadUrl;
  final int size;
  final DateTime? publishedAt;
  final String body;
}

enum UpdateDownloadStatus {
  idle,
  downloading,
  downloaded,
  failed,
}

class UpdateDownloadState {
  const UpdateDownloadState({
    required this.status,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.filePath,
    this.errorMessage,
  });

  const UpdateDownloadState.idle() : this(status: UpdateDownloadStatus.idle);

  final UpdateDownloadStatus status;
  final int receivedBytes;
  final int totalBytes;
  final String? filePath;
  final String? errorMessage;

  bool get isDownloading => status == UpdateDownloadStatus.downloading;

  bool get isDownloaded => status == UpdateDownloadStatus.downloaded;

  double? get progress {
    if (totalBytes <= 0) {
      return null;
    }
    return (receivedBytes / totalBytes).clamp(0, 1).toDouble();
  }
}
