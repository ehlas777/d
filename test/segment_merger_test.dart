import 'package:flutter_test/flutter_test.dart';
import 'package:polydub/services/video_splitter_service.dart';
import 'package:polydub/models/transcription_result.dart';

void main() {
  group('Segment Merging Logic', () {
    final service = VideoSplitterService();

    TranscriptionSegment createSegment(int index) {
      return TranscriptionSegment(
        start: index * 1.0,
        end: (index + 1) * 1.0,
        text: 'Segment $index',
        language: 'en',
      );
    }

    test('Should not merge when count < 30', () {
      final segments = List.generate(29, (i) => createSegment(i));
      final merged = service.mergeSegments(segments);
      expect(merged.length, 29);
      expect(merged[0].text, 'Segment 0');
    });

    test('Should merge every 2 segments when count is 30-49', () {
      final segments = List.generate(30, (i) => createSegment(i));
      final merged = service.mergeSegments(segments);
      
      // 30 / 2 = 15 segments
      expect(merged.length, 15);
      
      // Check first merged segment
      // Should be Segment 0 + Segment 1 joined by newline
      expect(merged[0].text, 'Segment 0\nSegment 1');
      expect(merged[0].start, 0.0);
      expect(merged[0].end, 2.0);
    });

    test('Should merge every 3 segments when count is 50-99', () {
      final segments = List.generate(50, (i) => createSegment(i));
      final merged = service.mergeSegments(segments);
      
      // 50 / 3 = 16.66 -> 17 segments (last one might be smaller)
      // ceil(50/3) = 17
      expect(merged.length, 17);
      
      expect(merged[0].text, 'Segment 0\nSegment 1\nSegment 2');
    });
    
    test('Should merge every 4 segments when count is 100-199', () {
      final segments = List.generate(100, (i) => createSegment(i));
      final merged = service.mergeSegments(segments);
      expect(merged.length, 25); // 100 / 4 = 25
      expect(merged[0].text, 'Segment 0\nSegment 1\nSegment 2\nSegment 3');
    });

    test('Should use newline separator for all merges', () {
      final segments = List.generate(40, (i) => createSegment(i)); // Merges by 2
      final merged = service.mergeSegments(segments);
      
      for (final segment in merged) {
        expect(segment.text, contains('\n'));
        expect(segment.text, isNot(contains('Segment 0 Segment 1'))); // Check for space
      }
    });
  });
}
