import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/features/voice_assistant/domain/services/transcript_manager.dart';

void main() {
  group('TranscriptManager (VOICE-009)', () {
    test('1. Final revises partial cleanly without duplicating clause', () {
      final manager = TranscriptManager();
      manager.beginTurn(sessionId: 's1', attemptId: 1);

      expect(
        manager.onPartial(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'ăn phở 50',
        ),
        isTrue,
      );
      expect(manager.state.committedSegments, isEmpty);
      expect(manager.currentPartial, 'ăn phở 50');
      expect(manager.effectiveText, 'ăn phở 50');

      expect(
        manager.onFinal(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 2,
          text: 'Ăn phở 55 nghìn',
        ),
        isTrue,
      );
      expect(manager.currentPartial, isEmpty);
      expect(manager.state.finalSegment, 'Ăn phở 55 nghìn');
      expect(manager.state.committedSegments, const <String>[
        'Ăn phở 55 nghìn',
      ]);
      expect(manager.effectiveText, 'Ăn phở 55 nghìn');
    });

    test(
      '2. Partial shrinks and revises mid-speech words without blocking',
      () {
        final manager = TranscriptManager();
        manager.beginTurn(sessionId: 's1', attemptId: 1);

        manager.onPartial(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'mua cà phê đá 30',
        );
        expect(manager.effectiveText, 'mua cà phê đá 30');

        // Recognizer revises to a shorter string mid-utterance
        manager.onPartial(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 2,
          text: 'mua cà phê',
        );
        expect(manager.effectiveText, 'mua cà phê');
        expect(manager.state.committedSegments, isEmpty);

        manager.onPartial(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 3,
          text: 'mua cà phê sữa 35 nghìn',
        );
        expect(manager.effectiveText, 'mua cà phê sữa 35 nghìn');
      },
    );

    test(
      '3. Duplicate partial text does not duplicate or mutate committed',
      () {
        final manager = TranscriptManager();
        manager.beginTurn(sessionId: 's1', attemptId: 1);

        expect(
          manager.onPartial(
            sessionId: 's1',
            attemptId: 1,
            sequenceNumber: 1,
            text: 'ăn cơm',
          ),
          isTrue,
        );
        expect(
          manager.onPartial(
            sessionId: 's1',
            attemptId: 1,
            sequenceNumber: 2,
            text: 'ăn cơm',
          ),
          isTrue,
        );
        expect(manager.state.committedSegments, isEmpty);
        expect(manager.effectiveText, 'ăn cơm');

        // Exact duplicate sequence number is rejected
        expect(
          manager.onPartial(
            sessionId: 's1',
            attemptId: 1,
            sequenceNumber: 2,
            text: 'ăn cơm trưa',
          ),
          isFalse,
        );
        expect(manager.effectiveText, 'ăn cơm');
      },
    );

    test('4. Late final from stale session is dropped', () {
      final manager = TranscriptManager();
      manager.beginTurn(sessionId: 's1', attemptId: 1);
      manager.onFinal(
        sessionId: 's1',
        attemptId: 1,
        sequenceNumber: 1,
        text: 'Ăn sáng 30 nghìn',
      );

      // Next session starts
      manager.beginTurn(sessionId: 's2', attemptId: 1, clearExisting: false);
      expect(
        manager.onFinal(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 2,
          text: 'Trà sữa 45 nghìn',
        ),
        isFalse,
      );
      expect(manager.effectiveText, 'Ăn sáng 30 nghìn');
    });

    test('5. Out-of-order sequence numbers are dropped cleanly', () {
      final manager = TranscriptManager();
      manager.beginTurn(sessionId: 's1', attemptId: 1);

      expect(
        manager.onPartial(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 5,
          text: 'mua cơm 40 nghìn',
        ),
        isTrue,
      );
      expect(
        manager.onPartial(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 3,
          text: 'mua',
        ),
        isFalse,
      );
      expect(
        manager.onFinal(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 4,
          text: 'mua cũ',
        ),
        isFalse,
      );
      expect(manager.effectiveText, 'mua cơm 40 nghìn');
    });

    test(
      '6. Append after pause merges smartly and dedupes cumulative overlap',
      () {
        final manager = TranscriptManager();
        manager.beginTurn(sessionId: 's1', attemptId: 1);
        manager.onFinal(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'Ăn phở 55 nghìn',
        );

        // Pause then start turn 2 without clearing
        manager.beginTurn(sessionId: 's2', attemptId: 1, clearExisting: false);
        // Cumulative re-emit lacking diacritics & with punctuation variation
        manager.onFinal(
          sessionId: 's2',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'An pho 55 nghin, Cà phê 35 nghìn',
        );
        expect(manager.effectiveText, 'Ăn phở 55 nghìn, Cà phê 35 nghìn');

        // Pause then turn 3 with independent utterance starting with common verb "ăn"
        manager.beginTurn(sessionId: 's3', attemptId: 1, clearExisting: false);
        manager.onFinal(
          sessionId: 's3',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'Ăn tối 80 nghìn',
        );
        expect(
          manager.effectiveText,
          'Ăn phở 55 nghìn, Cà phê 35 nghìn, Ăn tối 80 nghìn',
        );
      },
    );

    test(
      '6b. Smart separator joins incomplete connector or bare digit with space',
      () {
        final manager = TranscriptManager();
        manager.beginTurn(sessionId: 's1', attemptId: 1);
        manager.onFinal(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'Mua cam và',
        );
        manager.beginTurn(sessionId: 's2', attemptId: 1);
        manager.onPartial(
          sessionId: 's2',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'táo 30',
        );
        expect(manager.effectiveText, 'Mua cam và táo 30');

        manager.onFinal(
          sessionId: 's2',
          attemptId: 1,
          sequenceNumber: 2,
          text: 'táo 30',
        );
        manager.beginTurn(sessionId: 's3', attemptId: 1);
        manager.onPartial(
          sessionId: 's3',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'nghìn',
        );
        expect(manager.effectiveText, 'Mua cam và táo 30 nghìn');
      },
    );

    test(
      '7. User edit preservation blocks partial overwrite and promotes on next turn',
      () {
        final manager = TranscriptManager();
        manager.beginTurn(sessionId: 's1', attemptId: 1);
        manager.onFinal(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'Ăn phở 55 nghìn',
        );

        manager.onUserEdit('Ăn phở bò 60 nghìn');
        expect(manager.effectiveText, 'Ăn phở bò 60 nghìn');

        // Stray partial from active session must NOT overwrite user edit
        expect(
          manager.onPartial(
            sessionId: 's1',
            attemptId: 1,
            sequenceNumber: 2,
            text: 'Ăn phở 50',
          ),
          isFalse,
        );
        expect(manager.effectiveText, 'Ăn phở bò 60 nghìn');

        // Next mic turn promotes user edit into committed segments
        manager.beginTurn(sessionId: 's2', attemptId: 1, clearExisting: false);
        expect(manager.state.userEditedText, isNull);
        expect(manager.state.committedSegments, const <String>[
          'Ăn phở bò 60 nghìn',
        ]);

        manager.onFinal(
          sessionId: 's2',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'Trà đá 5 nghìn',
        );
        expect(manager.effectiveText, 'Ăn phở bò 60 nghìn, Trà đá 5 nghìn');
      },
    );

    test('8. Stale attemptId dropped and empty final honors rescue flag', () {
      final manager = TranscriptManager();
      manager.beginTurn(sessionId: 's1', attemptId: 2);

      // Event from attemptId 1 dropped
      expect(
        manager.onPartial(
          sessionId: 's1',
          attemptId: 1,
          sequenceNumber: 1,
          text: 'cũ',
        ),
        isFalse,
      );

      // Valid partial then empty final WITHOUT rescue discards partial
      manager.onPartial(
        sessionId: 's1',
        attemptId: 2,
        sequenceNumber: 1,
        text: 'Đổ xăng 70 nghìn',
      );
      manager.onFinal(
        sessionId: 's1',
        attemptId: 2,
        sequenceNumber: 2,
        text: '   ',
        rescuePartialOnEmptyFinal: false,
      );
      expect(manager.effectiveText, isEmpty);

      // Valid partial then empty final WITH rescue promotes partial
      manager.onPartial(
        sessionId: 's1',
        attemptId: 2,
        sequenceNumber: 3,
        text: 'Đổ xăng 70 nghìn',
      );
      manager.onFinal(
        sessionId: 's1',
        attemptId: 2,
        sequenceNumber: 4,
        text: '',
        rescuePartialOnEmptyFinal: true,
      );
      expect(manager.effectiveText, 'Đổ xăng 70 nghìn');
    });
  });
}
