import 'dart:async';

/// Lightweight, deterministic stream combiner using `Stream.multi` that cancels all
/// upstream subscriptions immediately when the downstream BLoC handler cancels or disposes.
abstract final class StreamCombiner {
  static Stream<R> combine2<A, B, R>(
    Stream<A> streamA,
    Stream<B> streamB,
    R Function(A a, B b) combiner,
  ) {
    return Stream<R>.multi((controller) {
      StreamSubscription<A>? subA;
      StreamSubscription<B>? subB;
      A? lastA;
      B? lastB;
      var hasA = false;
      var hasB = false;

      void tryEmit() {
        if (hasA && hasB && !controller.isClosed) {
          controller.addSync(combiner(lastA as A, lastB as B));
        }
      }

      subA = streamA.listen(
        (a) {
          lastA = a;
          hasA = true;
          tryEmit();
        },
        onError: controller.addErrorSync,
      );

      subB = streamB.listen(
        (b) {
          lastB = b;
          hasB = true;
          tryEmit();
        },
        onError: controller.addErrorSync,
      );

      controller.onCancel = () async {
        await subA?.cancel();
        await subB?.cancel();
      };
    });
  }

  static Stream<R> combine3<A, B, C, R>(
    Stream<A> streamA,
    Stream<B> streamB,
    Stream<C> streamC,
    R Function(A a, B b, C c) combiner,
  ) {
    return combine2<({A a, B b}), C, R>(
      combine2<A, B, ({A a, B b})>(streamA, streamB, (a, b) => (a: a, b: b)),
      streamC,
      (ab, c) => combiner(ab.a, ab.b, c),
    );
  }

  static Stream<R> combine4<A, B, C, D, R>(
    Stream<A> streamA,
    Stream<B> streamB,
    Stream<C> streamC,
    Stream<D> streamD,
    R Function(A a, B b, C c, D d) combiner,
  ) {
    return combine2<({A a, B b, C c}), D, R>(
      combine3<A, B, C, ({A a, B b, C c})>(
        streamA,
        streamB,
        streamC,
        (a, b, c) => (a: a, b: b, c: c),
      ),
      streamD,
      (abc, d) => combiner(abc.a, abc.b, abc.c, d),
    );
  }
}
