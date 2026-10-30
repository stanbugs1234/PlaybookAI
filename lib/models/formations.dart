import 'play.dart';
import 'vec.dart';

/// Formation presets. Player ids are stable across formations so assignments
/// can survive a formation change:
///   lt lg c rg rt — offensive line
///   qb            — quarterback
///   x z           — outside receivers (X weak/left, Z strong/right)
///   y             — tight end or #2/#3 receiver
///   h             — slot, fullback or second back
///   f             — tailback
abstract final class Formations {
  static const double _c = Field.center;
  static const double _olY = -0.8;

  static List<OffPlayer> _line() => const [
        OffPlayer(id: 'lt', role: Role.ol, label: 'LT', pos: Vec(_c - 3.6, _olY)),
        OffPlayer(id: 'lg', role: Role.ol, label: 'LG', pos: Vec(_c - 1.8, _olY)),
        OffPlayer(id: 'c', role: Role.ol, label: 'C', pos: Vec(_c, _olY)),
        OffPlayer(id: 'rg', role: Role.ol, label: 'RG', pos: Vec(_c + 1.8, _olY)),
        OffPlayer(id: 'rt', role: Role.ol, label: 'RT', pos: Vec(_c + 3.6, _olY)),
      ];

  static const _gunQb = OffPlayer(id: 'qb', role: Role.qb, label: 'QB', pos: Vec(_c, -5));
  static const _ucQb = OffPlayer(id: 'qb', role: Role.qb, label: 'QB', pos: Vec(_c, -1.6));

  static final Map<String, List<OffPlayer> Function()> presets = {
    'Gun Trips Right': () => [
          ..._line(),
          _gunQb,
          const OffPlayer(id: 'x', role: Role.wr, label: 'X', pos: Vec(5, -1)),
          const OffPlayer(id: 'z', role: Role.wr, label: 'Z', pos: Vec(48.5, -1.5)),
          const OffPlayer(id: 'h', role: Role.wr, label: 'H', pos: Vec(41, -1.5)),
          const OffPlayer(id: 'y', role: Role.wr, label: 'Y', pos: Vec(35.5, -1.5)),
          const OffPlayer(id: 'f', role: Role.rb, label: 'F', pos: Vec(_c - 1.6, -5)),
        ],
    'Gun Doubles': () => [
          ..._line(),
          _gunQb,
          const OffPlayer(id: 'x', role: Role.wr, label: 'X', pos: Vec(5, -1)),
          const OffPlayer(id: 'h', role: Role.wr, label: 'H', pos: Vec(13, -1.5)),
          const OffPlayer(id: 'y', role: Role.wr, label: 'Y', pos: Vec(40, -1.5)),
          const OffPlayer(id: 'z', role: Role.wr, label: 'Z', pos: Vec(48.5, -1.5)),
          const OffPlayer(id: 'f', role: Role.rb, label: 'F', pos: Vec(_c + 1.6, -5)),
        ],
    'Gun Trey (TE)': () => [
          ..._line(),
          _gunQb,
          const OffPlayer(id: 'x', role: Role.wr, label: 'X', pos: Vec(5, -1)),
          const OffPlayer(id: 'h', role: Role.wr, label: 'H', pos: Vec(41, -1.5)),
          const OffPlayer(id: 'y', role: Role.te, label: 'Y', pos: Vec(_c + 5.4, -1)),
          const OffPlayer(id: 'z', role: Role.wr, label: 'Z', pos: Vec(48.5, -1.5)),
          const OffPlayer(id: 'f', role: Role.rb, label: 'F', pos: Vec(_c - 1.6, -5)),
        ],
    'Singleback Ace': () => [
          ..._line(),
          _ucQb,
          const OffPlayer(id: 'x', role: Role.wr, label: 'X', pos: Vec(6, -1)),
          const OffPlayer(id: 'h', role: Role.wr, label: 'H', pos: Vec(14, -1.5)),
          const OffPlayer(id: 'y', role: Role.te, label: 'Y', pos: Vec(_c + 5.4, -1)),
          const OffPlayer(id: 'z', role: Role.wr, label: 'Z', pos: Vec(47.5, -1.5)),
          const OffPlayer(id: 'f', role: Role.rb, label: 'F', pos: Vec(_c, -6.5)),
        ],
    'I-Form Pro': () => [
          ..._line(),
          _ucQb,
          const OffPlayer(id: 'x', role: Role.wr, label: 'X', pos: Vec(6, -1)),
          const OffPlayer(id: 'y', role: Role.te, label: 'Y', pos: Vec(_c + 5.4, -1)),
          const OffPlayer(id: 'z', role: Role.wr, label: 'Z', pos: Vec(47.5, -1.5)),
          const OffPlayer(id: 'h', role: Role.fb, label: 'H', pos: Vec(_c, -4.2)),
          const OffPlayer(id: 'f', role: Role.rb, label: 'F', pos: Vec(_c, -7)),
        ],
    'Gun Bunch Right': () => [
          ..._line(),
          _gunQb,
          const OffPlayer(id: 'x', role: Role.wr, label: 'X', pos: Vec(5, -1)),
          const OffPlayer(id: 'y', role: Role.wr, label: 'Y', pos: Vec(38, -1)),
          const OffPlayer(id: 'z', role: Role.wr, label: 'Z', pos: Vec(39.6, -2.4)),
          const OffPlayer(id: 'h', role: Role.wr, label: 'H', pos: Vec(36.4, -2.4)),
          const OffPlayer(id: 'f', role: Role.rb, label: 'F', pos: Vec(_c - 1.6, -5)),
        ],
    'Gun Empty': () => [
          ..._line(),
          _gunQb,
          const OffPlayer(id: 'x', role: Role.wr, label: 'X', pos: Vec(5, -1)),
          const OffPlayer(id: 'h', role: Role.wr, label: 'H', pos: Vec(12.5, -1.5)),
          const OffPlayer(id: 'f', role: Role.rb, label: 'F', pos: Vec(36, -1.5)),
          const OffPlayer(id: 'y', role: Role.wr, label: 'Y', pos: Vec(42, -1.5)),
          const OffPlayer(id: 'z', role: Role.wr, label: 'Z', pos: Vec(48.5, -1)),
        ],
  };

  static List<String> get names => presets.keys.toList();

  static List<OffPlayer> build(String name) =>
      (presets[name] ?? presets.values.first)();
}
