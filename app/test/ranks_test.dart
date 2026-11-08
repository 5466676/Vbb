import 'package:flutter_test/flutter_test.dart';
import 'package:harb_al_oqool/core/ranks.dart';

void main() {
  test('match experience and ranks follow GAME_RULES §9', () {
    expect(matchXp(0, false), 10);
    expect(matchXp(8, true), 80);
    expect([for (final x in [0, 199, 200, 600, 1500, 3500, 7000]) rankOf(x)], ['E', 'E', 'D', 'C', 'B', 'A', 'S']);
    expect(levelOf(250), 3);
    expect(rankProgress(400), 0.5);
    expect(toNextRank(400), 200);
    expect(toNextRank(9000), 0);
    expect(rankOf(botXp['hard']!), 'A');
  });
}
