class TransferFile {
  const TransferFile({
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    this.localPath,
    this.savePath,
  });

  final String fileName;
  final int fileSize;
  final String sha256;
  final String? localPath;
  final String? savePath;

  TransferFile copyWith({
    String? fileName,
    int? fileSize,
    String? sha256,
    String? localPath,
    String? savePath,
  }) {
    return TransferFile(
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      sha256: sha256 ?? this.sha256,
      localPath: localPath ?? this.localPath,
      savePath: savePath ?? this.savePath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fileName': fileName,
      'fileSize': fileSize,
      'sha256': sha256,
    };
  }

  Map<String, dynamic> toHistoryJson() {
    return {
      'fileName': fileName,
      'fileSize': fileSize,
      'sha256': sha256,
      'localPath': localPath,
      'savePath': savePath,
    };
  }

  factory TransferFile.fromJson(Map<String, dynamic> json) {
    return TransferFile(
      fileName: json['fileName'] as String? ?? 'file',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String? ?? '',
      localPath: json['localPath'] as String?,
      savePath: json['savePath'] as String?,
    );
  }
}
