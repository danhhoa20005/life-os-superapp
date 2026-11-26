Future<R> runBackupCryptoTask<R>(R Function() task) => Future<R>.sync(task);
