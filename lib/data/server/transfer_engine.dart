import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import 'credential_vault.dart';
import 'server_session.dart';
import 'webdav_client.dart';

/// What to do with the source once the copy has landed.
enum TransferMode {
  /// Leave the source alone.
  copy,

  /// Delete the source, but only after the destination is verified.
  move,
}

enum TransferStatus { queued, running, completed, failed, cancelled }

/// Why a job failed, for a UI that wants to offer the right way out —
/// [collision] in particular is the one worth an "Overwrite?" prompt rather
/// than an error toast.
enum TransferFailure {
  /// Something already exists at the destination and `overwrite` was false.
  collision,

  /// The source is gone, or the destination folder does not exist.
  notFound,

  /// The server rejected the credentials, or none are stored.
  auth,

  /// The server could not be reached, or the connection dropped.
  network,

  /// The server answered, but not in a way that makes sense.
  server,

  /// The upload finished but the destination does not match the source. The
  /// source is never deleted after this.
  verification,

  /// The source or destination server is not connected.
  notConnected,
}

/// One queued or running file transfer.
///
/// Immutable: the engine replaces the whole job on every change, so a listener
/// that captured an old one sees a consistent snapshot rather than a
/// half-updated object.
class TransferJob {
  const TransferJob({
    required this.id,
    required this.srcServerId,
    required this.srcPath,
    required this.dstServerId,
    required this.dstDir,
    required this.mode,
    this.overwrite = false,
    this.status = TransferStatus.queued,
    this.transferredBytes = 0,
    this.totalBytes,
    this.error,
    this.failure,
  });

  final String id;
  final String srcServerId;
  final String srcPath;
  final String dstServerId;

  /// The destination *folder*; the file keeps its name.
  final String dstDir;

  final TransferMode mode;

  /// Whether an existing file at [dstPath] may be replaced. False means a
  /// collision fails the job instead, leaving the decision to the user.
  final bool overwrite;

  final TransferStatus status;
  final int transferredBytes;

  /// Null until the source has been sized, and stays null if the server never
  /// reports a length.
  final int? totalBytes;

  /// Safe to show the user verbatim.
  final String? error;

  final TransferFailure? failure;

  /// Where the file ends up.
  String get dstPath =>
      WebDavClient.joinPath(dstDir, WebDavClient.basename(srcPath));

  String get name => WebDavClient.basename(srcPath);

  bool get isFinished =>
      status == TransferStatus.completed ||
      status == TransferStatus.failed ||
      status == TransferStatus.cancelled;

  /// 0..1, or null while the total is unknown — which the UI must render as
  /// an indeterminate bar rather than as 0%.
  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (transferredBytes / total).clamp(0.0, 1.0);
  }

  TransferJob copyWith({
    TransferStatus? status,
    int? transferredBytes,
    int? totalBytes,
    String? error,
    TransferFailure? failure,
  }) {
    return TransferJob(
      id: id,
      srcServerId: srcServerId,
      srcPath: srcPath,
      dstServerId: dstServerId,
      dstDir: dstDir,
      mode: mode,
      overwrite: overwrite,
      status: status ?? this.status,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
      failure: failure ?? this.failure,
    );
  }

  @override
  String toString() => 'TransferJob($id, ${status.name}, $srcPath -> $dstPath)';
}

/// Finds the client for a server id, or null if it is not connected.
typedef TransferClientResolver = WebDavClient? Function(String serverId);

/// Moves and copies files between servers.
///
/// The cross-server path pipes the download stream straight into the upload
/// stream, so a 2 GB album costs a socket buffer rather than 2 GB of RAM, and
/// progress comes from counting bytes as they pass rather than from guessing.
///
/// Three rules the tests pin down, because getting them wrong loses data:
///
/// * A move deletes the source **only** after the destination has been read
///   back and matches. An upload that reports success but leaves nothing
///   behind must not take the original with it.
/// * A cancellation never deletes the source, at any point in the transfer.
/// * A name collision fails the job instead of overwriting, unless the caller
///   asked for `overwrite`.
class TransferEngine extends StateNotifier<List<TransferJob>> {
  TransferEngine({
    required TransferClientResolver clients,
    this.maxConcurrent = AppConstants.maxConcurrentTransfers,
  })  : _clients = clients,
        super(const []);

  final TransferClientResolver _clients;

  /// FIFO beyond this many. Two is enough to keep a fast server busy while a
  /// slow one crawls, without turning a home NAS into a queue of stalled
  /// sockets.
  final int maxConcurrent;

  static const _uuid = Uuid();

  /// A tick is emitted when either threshold is passed, so a small file still
  /// reports progress and a large one does not flood listeners.
  static const _tickInterval = Duration(milliseconds: 60);
  static const _tickBytes = 64 * 1024;

  final _running = <String>{};
  final _cancelled = <String>{};
  final _lastTickAt = <String, DateTime>{};
  final _lastTickBytes = <String, int>{};
  final _idleWaiters = <Completer<void>>[];

  /// Queues a transfer and returns its job id.
  ///
  /// Nothing starts until a slot is free. `dstDir` must be an existing folder
  /// on the destination server; the file keeps its name.
  String enqueue({
    required String srcServerId,
    required String srcPath,
    required String dstServerId,
    required String dstDir,
    TransferMode mode = TransferMode.copy,
    bool overwrite = false,
    int? totalBytes,
  }) {
    final job = TransferJob(
      id: _uuid.v4(),
      srcServerId: srcServerId,
      srcPath: WebDavClient.normalizePath(srcPath),
      dstServerId: dstServerId,
      dstDir: WebDavClient.normalizePath(dstDir),
      mode: mode,
      overwrite: overwrite,
      totalBytes: totalBytes,
    );
    state = [...state, job];
    _pump();
    return job.id;
  }

  /// Asks a job to stop.
  ///
  /// A queued job stops at once. A running one stops at the next chunk or the
  /// next checkpoint; either way the source survives and a partly written
  /// destination file is removed, unless it was already there before the job
  /// started.
  void cancel(String jobId) {
    final job = _job(jobId);
    if (job == null || job.isFinished) return;
    _cancelled.add(jobId);
    if (job.status == TransferStatus.queued) {
      _cancelled.remove(jobId);
      _finish(jobId, job.copyWith(status: TransferStatus.cancelled));
    }
  }

  /// Drops completed, failed and cancelled jobs from the list. Running and
  /// queued jobs stay.
  void clearFinished() {
    state = state.where((job) => !job.isFinished).toList();
  }

  /// The queue as it stands, newest last. Watching `transferEngineProvider` is
  /// the usual way to read this; the getter is for code that holds the engine
  /// directly.
  List<TransferJob> get jobs => state;

  TransferJob? jobById(String jobId) => _job(jobId);

  /// Completes when nothing is running or queued. Mainly for tests; a UI
  /// should watch the job list instead.
  Future<void> whenIdle() {
    if (_running.isEmpty &&
        !state.any((j) => j.status == TransferStatus.queued)) {
      return Future.value();
    }
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  TransferJob? _job(String jobId) {
    for (final job in state) {
      if (job.id == jobId) return job;
    }
    return null;
  }

  void _update(String jobId, TransferJob updated) {
    if (!mounted) return;
    state = [
      for (final job in state)
        if (job.id == jobId) updated else job,
    ];
  }

  void _finish(String jobId, TransferJob updated) {
    _running.remove(jobId);
    _lastTickAt.remove(jobId);
    _lastTickBytes.remove(jobId);
    _update(jobId, updated);
    _pump();
  }

  void _pump() {
    if (!mounted) return;
    while (_running.length < maxConcurrent) {
      TransferJob? next;
      for (final job in state) {
        if (job.status == TransferStatus.queued && !_running.contains(job.id)) {
          next = job;
          break;
        }
      }
      if (next == null) break;
      _running.add(next.id);
      _update(next.id, next.copyWith(status: TransferStatus.running));
      unawaited(_run(next.id));
    }

    if (_running.isEmpty &&
        !state.any((job) => job.status == TransferStatus.queued)) {
      final waiters = List<Completer<void>>.from(_idleWaiters);
      _idleWaiters.clear();
      for (final waiter in waiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }
  }

  Future<void> _run(String jobId) async {
    var job = _job(jobId);
    if (job == null) {
      // Cleared out from under us; nothing to report, just free the slot.
      _running.remove(jobId);
      _pump();
      return;
    }

    final src = _clients(job.srcServerId);
    final dst = _clients(job.dstServerId);
    if (src == null || dst == null) {
      _fail(
        jobId,
        'That server is not connected.',
        TransferFailure.notConnected,
      );
      return;
    }

    var createdDestination = false;
    try {
      if (_stopped(jobId)) return _cancel(jobId, dst, false);

      final source = await src.stat(job.srcPath);
      if (source == null) {
        _fail(
          jobId,
          'The file is no longer on the server.',
          TransferFailure.notFound,
        );
        return;
      }
      job = job.copyWith(totalBytes: source.size);
      _update(jobId, job);

      final existing = await dst.stat(job.dstPath);
      if (existing != null && !job.overwrite) {
        _fail(
          jobId,
          '${job.name} already exists in ${job.dstDir}.',
          TransferFailure.collision,
        );
        return;
      }
      createdDestination = existing == null;

      if (_stopped(jobId)) return _cancel(jobId, dst, false);

      // Same server, and the file is only changing folders: let the server do
      // it. No bytes cross the network and there is nothing to verify, since
      // MOVE either happened or it did not.
      if (job.srcServerId == job.dstServerId && job.mode == TransferMode.move) {
        await src.moveSameServer(
          job.srcPath,
          job.dstPath,
          overwrite: job.overwrite,
        );
        _finish(
          jobId,
          job.copyWith(
            status: TransferStatus.completed,
            transferredBytes: job.totalBytes ?? 0,
          ),
        );
        return;
      }

      final download = await src.download(job.srcPath);
      final total = job.totalBytes ?? download.contentLength;
      if (total != job.totalBytes) {
        job = job.copyWith(totalBytes: total);
        _update(jobId, job);
      }

      var sent = 0;
      final piped = download.stream.map((chunk) {
        if (_stopped(jobId)) throw const _CancelledSignal();
        sent += chunk.length;
        _tick(jobId, sent);
        return chunk;
      });

      await dst.upload(
        job.dstPath,
        piped,
        total,
        overwrite: job.overwrite,
        contentType: source.contentType,
      );

      if (_stopped(jobId)) return _cancel(jobId, dst, createdDestination);

      // Read the destination back before touching the source. A PUT that
      // answers 201 and writes nothing is rare but not hypothetical, and a
      // move that trusted the status code would delete the only copy.
      final landed = await dst.stat(job.dstPath);
      if (landed == null) {
        _fail(
          jobId,
          'The upload finished but ${job.name} is not on the destination '
          'server.',
          TransferFailure.verification,
        );
        return;
      }
      if (total != null && landed.size != null && landed.size != total) {
        _fail(
          jobId,
          'The copy of ${job.name} is ${landed.size} bytes but the original '
          'is $total.',
          TransferFailure.verification,
        );
        return;
      }

      if (job.mode == TransferMode.move) {
        await src.delete(job.srcPath);
      }

      _finish(
        jobId,
        job.copyWith(
          status: TransferStatus.completed,
          transferredBytes: total ?? sent,
        ),
      );
    } catch (error) {
      if (_stopped(jobId)) {
        await _cancel(jobId, dst, createdDestination);
        return;
      }
      final failure = _classify(error);
      _fail(jobId, describeServerError(error), failure);
      // A failed cross-server copy can leave a partial file behind; it was not
      // there before, so removing it is a cleanup rather than a deletion.
      if (createdDestination && failure != TransferFailure.collision) {
        await _removeQuietly(dst, _job(jobId)?.dstPath);
      }
    }
  }

  bool _stopped(String jobId) => _cancelled.contains(jobId);

  Future<void> _cancel(
    String jobId,
    WebDavClient? dst,
    bool createdDestination,
  ) async {
    final job = _job(jobId);
    if (createdDestination && dst != null && job != null) {
      await _removeQuietly(dst, job.dstPath);
    }
    _cancelled.remove(jobId);
    if (job != null) {
      _finish(jobId, job.copyWith(status: TransferStatus.cancelled));
    } else {
      _running.remove(jobId);
      _pump();
    }
  }

  /// Cleanup must not turn one failure into two, so anything that goes wrong
  /// deleting a partial file is dropped.
  Future<void> _removeQuietly(WebDavClient client, String? path) async {
    if (path == null) return;
    try {
      await client.delete(path);
    } catch (_) {
      // Nothing useful to do: the transfer already failed or was cancelled.
    }
  }

  void _fail(String jobId, String message, TransferFailure failure) {
    final job = _job(jobId);
    if (job == null) return;
    _finish(
      jobId,
      job.copyWith(
        status: TransferStatus.failed,
        error: message,
        failure: failure,
      ),
    );
  }

  TransferFailure _classify(Object error) {
    if (error is WebDavConflictException) return TransferFailure.collision;
    if (error is WebDavNotFoundException) return TransferFailure.notFound;
    if (error is WebDavAuthException) return TransferFailure.auth;
    if (error is WebDavNetworkException) return TransferFailure.network;
    if (error is VaultException) return TransferFailure.auth;
    return TransferFailure.server;
  }

  void _tick(String jobId, int sent) {
    final now = DateTime.now();
    final lastAt = _lastTickAt[jobId];
    final lastBytes = _lastTickBytes[jobId] ?? 0;
    final due = lastAt == null ||
        now.difference(lastAt) >= _tickInterval ||
        sent - lastBytes >= _tickBytes;
    if (!due) return;

    _lastTickAt[jobId] = now;
    _lastTickBytes[jobId] = sent;
    final job = _job(jobId);
    if (job == null || job.status != TransferStatus.running) return;
    _update(jobId, job.copyWith(transferredBytes: sent));
  }

  @override
  void dispose() {
    for (final waiter in _idleWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _idleWaiters.clear();
    super.dispose();
  }
}

/// Thrown into the piped stream to unwind a cancelled transfer. It never
/// escapes the engine: [TransferEngine] checks the cancel flag before deciding
/// what a failure means.
class _CancelledSignal implements Exception {
  const _CancelledSignal();
}
