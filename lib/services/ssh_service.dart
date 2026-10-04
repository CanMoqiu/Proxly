import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_host_trust_service.dart';
import 'ssh_authentication_deadline.dart';

class SshCommandResult {
  final String stdout;
  final String stderr;
  final int? exitCode;
  final String? exitSignal;

  const SshCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.exitSignal,
  });
}

class SshCommandException implements Exception {
  final String command;
  final int? exitCode;
  final String? exitSignal;
  final String stdout;
  final String stderr;

  const SshCommandException({
    required this.command,
    required this.exitCode,
    required this.exitSignal,
    required this.stdout,
    required this.stderr,
  });

  @override
  String toString() {
    final reason = exitSignal != null
        ? 'signal $exitSignal'
        : 'exit code ${exitCode ?? 'unknown'}';
    final detail = stderr.trim().isNotEmpty
        ? stderr.trim()
        : stdout.trim().isNotEmpty
            ? stdout.trim()
            : 'no command output';
    return 'SSH command failed ($reason): $detail';
  }
}

class SshService {
  static Future<T> withClient<T>(
    String host,
    String password,
    Future<T> Function(SSHClient client) action, {
    String username = 'root',
    int port = 22,
    Duration timeout = const Duration(seconds: 10),
    Duration authTimeout = const Duration(seconds: 15),
    Duration? operationTimeout,
    SSHHostkeyVerifyHandler? onVerifyHostKey,
  }) async {
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: timeout,
    );
    final deadline = SshAuthenticationDeadline(authTimeout);
    final client = SSHClient(
      socket,
      username: username,
      onVerifyHostKey: (type, fingerprint) => deadline.verify(() =>
          onVerifyHostKey?.call(type, fingerprint) ??
          SshHostTrustService.instance.verify(
            host,
            port,
            type,
            fingerprint,
          )),
      onPasswordRequest: () => password,
    );
    try {
      await deadline.waitFor(client.authenticated);
      final result = action(client);
      if (operationTimeout == null) return await result;
      return await result.timeout(
        operationTimeout,
        onTimeout: () => throw TimeoutException('SSH operation timed out'),
      );
    } finally {
      client.close();
      await client.done.catchError((_) {});
    }
  }

  static Future<void> execute(
    String host,
    String password,
    String command,
  ) {
    return withClient<void>(
      host,
      password,
      (client) async {
        await runCommandOnClient(client, command);
      },
      operationTimeout: const Duration(seconds: 30),
    );
  }

  static Future<SshCommandResult> runCommandOnClient(
    SSHClient client,
    String command,
  ) async {
    final session = await client.execute(command);
    final stdout = BytesBuilder(copy: false);
    final stderr = BytesBuilder(copy: false);
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    session.stdout.listen(
      stdout.add,
      onDone: stdoutDone.complete,
      onError: stdoutDone.completeError,
      cancelOnError: true,
    );
    session.stderr.listen(
      stderr.add,
      onDone: stderrDone.complete,
      onError: stderrDone.completeError,
      cancelOnError: true,
    );

    await Future.wait([
      stdoutDone.future,
      stderrDone.future,
      session.done,
    ]);

    final result = SshCommandResult(
      stdout: utf8.decode(stdout.takeBytes(), allowMalformed: true),
      stderr: utf8.decode(stderr.takeBytes(), allowMalformed: true),
      exitCode: session.exitCode,
      exitSignal: session.exitSignal?.signalName,
    );
    if (result.exitSignal != null ||
        (result.exitCode != null && result.exitCode != 0)) {
      throw SshCommandException(
        command: command,
        exitCode: result.exitCode,
        exitSignal: result.exitSignal,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    }
    return result;
  }

  static Future<String> runText(
    String host,
    String password,
    String command, {
    String username = 'root',
    int port = 22,
    bool stderr = false,
    Duration? operationTimeout,
  }) async {
    final result = await withClient(
      host,
      password,
      (client) => runCommandOnClient(client, command),
      username: username,
      port: port,
      operationTimeout: operationTimeout,
    );
    return stderr ? result.stdout + result.stderr : result.stdout;
  }
}
