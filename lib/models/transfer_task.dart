import 'transfer_file.dart';

enum TransferDirection {
  send('send'),
  receive('receive');

  const TransferDirection(this.value);
  final String value;

  static TransferDirection parse(String value) {
    return TransferDirection.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TransferDirection.send,
    );
  }
}

enum TransferStatus {
  pending('pending'),
  waitingAccept('waiting_accept'),
  transferring('transferring'),
  completed('completed'),
  failed('failed'),
  rejected('rejected'),
  cancelled('cancelled');

  const TransferStatus(this.value);
  final String value;

  static TransferStatus parse(String value) {
    return TransferStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () => TransferStatus.pending,
    );
  }
}

class TransferTask {
  const TransferTask({
    required this.taskId,
    required this.direction,
    required this.peerDeviceName,
    required this.files,
    required this.status,
    required this.totalBytes,
    required this.transferredBytes,
    required this.createdAt,
    required this.updatedAt,
    this.currentFileName,
    this.errorMessage,
    this.savePath,
  });

  final String taskId;
  final TransferDirection direction;
  final String peerDeviceName;
  final List<TransferFile> files;
  final TransferStatus status;
  final int totalBytes;
  final int transferredBytes;
  final String? currentFileName;
  final String? errorMessage;
  final String? savePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get progress {
    if (totalBytes <= 0) {
      return 0;
    }
    return (transferredBytes / totalBytes).clamp(0, 1);
  }

  double get speedBytesPerSecond {
    final seconds = updatedAt.difference(createdAt).inMilliseconds / 1000;
    if (seconds <= 0) {
      return 0;
    }
    return transferredBytes / seconds;
  }

  TransferTask copyWith({
    TransferDirection? direction,
    String? peerDeviceName,
    List<TransferFile>? files,
    TransferStatus? status,
    int? totalBytes,
    int? transferredBytes,
    String? currentFileName,
    String? errorMessage,
    String? savePath,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearError = false,
  }) {
    return TransferTask(
      taskId: taskId,
      direction: direction ?? this.direction,
      peerDeviceName: peerDeviceName ?? this.peerDeviceName,
      files: files ?? this.files,
      status: status ?? this.status,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      currentFileName: currentFileName ?? this.currentFileName,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      savePath: savePath ?? this.savePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

class TransferHistoryRecord {
  const TransferHistoryRecord({
    required this.taskId,
    required this.direction,
    required this.peerDeviceName,
    required this.fileName,
    required this.fileSize,
    required this.status,
    required this.createdAt,
    this.savePath,
  });

  final String taskId;
  final TransferDirection direction;
  final String peerDeviceName;
  final String fileName;
  final int fileSize;
  final TransferStatus status;
  final String? savePath;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'direction': direction.value,
      'peerDeviceName': peerDeviceName,
      'fileName': fileName,
      'fileSize': fileSize,
      'status': status.value,
      'savePath': savePath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TransferHistoryRecord.fromJson(Map<String, dynamic> json) {
    return TransferHistoryRecord(
      taskId: json['taskId'] as String,
      direction: TransferDirection.parse(json['direction'] as String? ?? 'send'),
      peerDeviceName: json['peerDeviceName'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      status: TransferStatus.parse(json['status'] as String? ?? 'completed'),
      savePath: json['savePath'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
