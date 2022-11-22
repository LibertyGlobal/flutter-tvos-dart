// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// TODO(jcollins-g): Merge this with similar utilities in dartdoc
// and extract into a separate package, generate testing and mirrors, and
// reimport that into the SDK, before cut and paste gets out of hand.

/// This is a modified version of dartdoc's
/// SubprocessLauncher from test/src/utils.dart, for use with the
/// nnbd_migration script.
library;

import 'dart:convert';
import 'dart:io';

import 'multi_future_tracker.dart';

/// Maximum number of parallel subprocesses.  Use this to to avoid overloading
/// your CPU.
final MultiFutureTracker maxParallel =
    MultiFutureTracker(Platform.numberOfProcessors);

/// Route all executions of pub through this [MultiFutureTracker] to avoid
/// parallel executions of the pub command.
final MultiFutureTracker pubTracker = MultiFutureTracker(1);

final RegExp quotables = RegExp(r'[ "\r\n\$]');

/// SubprocessLauncher manages one or more launched, non-interactive
/// subprocesses.  It handles I/O streams, parses JSON output if
/// available, and logs debugging information so the user can see exactly
/// what was run.
class SubprocessLauncher {
  final String context;
  final Map<String, String> environmentDefaults;

  SubprocessLauncher(this.context, [Map<String, String>? environment])
      : environmentDefaults = environment ?? <String, String>{};

  /// Wraps [runStreamedImmediate] as a closure around
  /// [maxParallel.addFutureFromClosure].
  ///
  /// This essentially implements a 'make -j N' limit for all subcommands.
  Future<Iterable<Map>?> runStreamed(String executable, List<String> arguments,
      // TODO(jcollins-g): Fix primitive obsession: consolidate parameters into
      // another object.
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      void Function(String)? perLine,
      int retries = 0,
      String? instance,
      bool allowNonzeroExit = false}) async {
    // TODO(jcollins-g): The closure wrapping we've done has made it impossible
    // to catch exceptions when calling runStreamed.  Fix this.
    return maxParallel.runFutureFromClosure(() async {
      return retryClosure(
          () async => await runStreamedImmediate(executable, arguments,
              workingDirectory: workingDirectory,
              environment: environment,
              includeParentEnvironment: includeParentEnvironment,
              perLine: perLine,
              instance: instance,
              allowNonzeroExit: allowNonzeroExit),
          retries: retries);
    });
  }

  /// A wrapper around start/await process.exitCode that will display the
  /// output of the executable continuously and fail on non-zero exit codes.
  /// It will also parse any valid JSON objects (one per line) it encounters
  /// on stdout/stderr, and return them.  Returns null if no JSON objects
  /// were encountered, or if DRY_RUN is set to 1 in the execution environment.
  ///
  /// Makes running programs in grinder similar to set -ex for bash, even on
  /// Windows (though some of the bashisms will no longer make sense).
  /// TODO(jcollins-g): refactor to return a stream of stderr/stdout lines
  ///                   and their associated JSON objects.
  Future<Iterable<Map>?> runStreamedImmediate(
      String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      void Function(String)? perLine,
      // A tag added to [context] to construct the line prefix.
      // Use this to indicate the process or processes with the tag
      // share something in common, like a hostname, a package, or a
      // multi-step procedure.
      String? instance,
      bool allowNonzeroExit = false}) async {
    String prefix = context.isNotEmpty
        ? '$context${instance != null ? "-$instance" : ""}: '
        : '';

    environment ??= {};
    environment.addAll(environmentDefaults);
    List<Map>? jsonObjects;

    /// Parses json objects generated by the subprocess.  If a json object
    /// contains the key 'message' or the keys 'data' and 'text', return that
    /// value as a collection of lines suitable for printing.
    Iterable<String> jsonCallback(String line) {
      if (perLine != null) perLine(line);
      Map? result;
      try {
        result = json.decoder.convert(line) as Map?;
      } on FormatException {
        // ignore
      }
      if (result != null) {
        jsonObjects ??= [];
        jsonObjects!.add(result);
        if (result.containsKey('message')) {
          line = result['message'] as String;
        } else if (result.containsKey('data') &&
            result['data'] is Map &&
            (result['data'] as Map).containsKey('key')) {
          line = result['data']['text'] as String;
        }
      }
      return line.split('\n');
    }

    stderr.write('$prefix+ ');
    if (workingDirectory != null) stderr.write('(cd "$workingDirectory" && ');
    stderr.write(environment.keys.map((String key) {
      if (environment![key]!.contains(quotables)) {
        return "$key='${environment[key]}'";
      } else {
        return '$key=${environment[key]}';
      }
    }).join(' '));
    stderr.write(' ');
    stderr.write(executable);
    if (arguments.isNotEmpty) {
      for (String arg in arguments) {
        if (arg.contains(quotables)) {
          stderr.write(" '$arg'");
        } else {
          stderr.write(' $arg');
        }
      }
    }
    if (workingDirectory != null) stderr.write(')');
    stderr.write('\n');

    if (Platform.environment.containsKey('DRY_RUN')) return null;

    String realExecutable = executable;
    final List<String> realArguments = [];
    if (Platform.isLinux) {
      // Use GNU coreutils to force line buffering.  This makes sure that
      // subprocesses that die due to fatal signals do not chop off the
      // last few lines of their output.
      //
      // Dart does not actually do this (seems to flush manually) unless
      // the VM crashes.
      realExecutable = 'stdbuf';
      realArguments.addAll(['-o', 'L', '-e', 'L']);
      realArguments.add(executable);
    }
    realArguments.addAll(arguments);

    Process process = await Process.start(realExecutable, realArguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment);
    Future<void> stdoutFuture = _printStream(process.stdout, stdout,
        prefix: prefix, filter: jsonCallback);
    Future<void> stderrFuture = _printStream(process.stderr, stderr,
        prefix: prefix, filter: jsonCallback);
    await Future.wait([stderrFuture, stdoutFuture, process.exitCode]);

    int exitCode = await process.exitCode;
    if (exitCode != 0 && !allowNonzeroExit) {
      throw ProcessException(executable, arguments,
          'SubprocessLauncher got non-zero exitCode: $exitCode', exitCode);
    }
    return jsonObjects;
  }

  /// From flutter:dev/tools/dartdoc.dart, modified.
  static Future<void> _printStream(Stream<List<int>> stream, Stdout output,
      {String prefix = '', Iterable<String> Function(String line)? filter}) {
    filter ??= (line) => [line];
    return stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .expand(filter)
        .listen((String line) {
      output.write('$prefix$line'.trim());
      output.write('\n');
    }).asFuture();
  }
}
