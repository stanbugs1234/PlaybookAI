import '../models/defense.dart';
import '../models/play.dart';
import '../models/vec.dart';

enum BallState { held, air, caught, dead }

class SimFrame {
  final double t;
  final Map<String, Vec> pos;
  final Vec ball;

  /// Ball height in yards (for drawing the arc of a pass).
  final double ballHeight;
  final BallState ballState;
  final String? carrierId;

  /// The receiver the QB is currently reading, if any.
  final String? eyes;

  const SimFrame({
    required this.t,
    required this.pos,
    required this.ball,
    required this.ballHeight,
    required this.ballState,
    required this.carrierId,
    required this.eyes,
  });
}

/// Why a read was (or wasn't) open.
enum ReadReason {
  open,
  notReady,
  overTop,
  manTight,
  undercut,
  zoneCloses,
  lane,
}

class ReadEval {
  final String receiverId;
  final double window; // yards of cushion when the ball would arrive
  final Vec catchPoint;
  final double flightTime;
  final String? limitingDefenderId;
  final ReadReason reason;
  final bool laneBlocked;

  const ReadEval({
    required this.receiverId,
    required this.window,
    required this.catchPoint,
    required this.flightTime,
    required this.limitingDefenderId,
    required this.reason,
    required this.laneBlocked,
  });
}

enum EventType {
  snap,
  unblocked,
  blitzPickup,
  fake,
  handoff,
  set,
  readStart,
  readCovered,
  pressure,
  throwBall,
  throwAway,
  complete,
  incomplete,
  interception,
  sack,
  brokenTackle,
  tackle,
  touchdown,
  outOfBounds,
}

class SimEvent {
  final EventType type;
  final double t;
  final int frame;
  final String? playerId;
  final String? defenderId;
  final int? readIndex;
  final ReadEval? eval;

  const SimEvent(this.type, this.t, this.frame,
      {this.playerId, this.defenderId, this.readIndex, this.eval});
}

enum OutcomeType {
  complete,
  incomplete,
  interception,
  sack,
  throwAway,
  run,
  touchdown,
}

class SimOutcome {
  final OutcomeType type;
  final double yards;
  final String? targetId;
  final double? timeToThrow;

  const SimOutcome(this.type, this.yards, {this.targetId, this.timeToThrow});

  bool get isSuccess =>
      type == OutcomeType.touchdown ||
      ((type == OutcomeType.complete || type == OutcomeType.run) && yards >= 4);

  String get label {
    final yds = '${yards >= 0 ? '+' : ''}${yards.toStringAsFixed(0)} yds';
    return switch (type) {
      OutcomeType.complete => 'Complete, $yds',
      OutcomeType.incomplete => 'Incomplete',
      OutcomeType.interception => 'Intercepted',
      OutcomeType.sack => 'Sack, $yds',
      OutcomeType.throwAway => 'Thrown away',
      OutcomeType.run => 'Run, $yds',
      OutcomeType.touchdown => 'Touchdown! $yds',
    };
  }
}

class SimResult {
  final Play play;
  final DefenseCall call;
  final List<Defender> defenders;
  final List<SimFrame> frames;
  final List<SimEvent> events;
  final SimOutcome outcome;
  final int seed;

  const SimResult({
    required this.play,
    required this.call,
    required this.defenders,
    required this.frames,
    required this.events,
    required this.outcome,
    required this.seed,
  });

  double get duration => frames.isEmpty ? 0 : frames.last.t;

  Defender? defender(String id) {
    for (final d in defenders) {
      if (d.id == id) return d;
    }
    return null;
  }
}
