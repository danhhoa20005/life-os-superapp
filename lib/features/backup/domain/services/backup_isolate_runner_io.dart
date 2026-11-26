import 'dart:isolate';

Future<R> runBackupCryptoTask<R>(R Function() task) => Isolate.run(task);
