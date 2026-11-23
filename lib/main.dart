import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void _enforceFullscreen() {
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _enforceFullscreen();
  runApp(const AuraluxApp());
}

class AuraluxApp extends StatelessWidget {
  const AuraluxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auralux: Constellations & Galaxies',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF02040A),
      ),
      home: const GameScreen(),
    );
  }
}

class CosmicAudioEngine {
  final AudioPlayer _bgmPlayer = AudioPlayer();
  final List<AudioPlayer> _sfxPool = List.generate(4, (_) => AudioPlayer());
  int _sfxIndex = 0;
  bool isMuted = false;
  bool _initialized = false;

  late Uint8List _bgmWav;
  late Uint8List _launchSfxWav;
  late Uint8List _upgradeSfxWav;
  late Uint8List _captureSfxWav;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _bgmWav = _generateSpaceAmbientWav(durationSec: 16.0, sampleRate: 22050);
    _launchSfxWav = _generateChordChimeWav(
      [523.25, 659.25, 783.99],
      durationSec: 0.45,
      volume: 0.35,
    );
    _upgradeSfxWav = _generateChordChimeWav(
      [261.63, 392.00, 523.25, 659.25, 1046.50],
      durationSec: 1.1,
      volume: 0.5,
      arpeggio: true,
    );
    _captureSfxWav = _generateChordChimeWav(
      [293.66, 440.00, 587.33, 880.00],
      durationSec: 0.85,
      volume: 0.45,
    );

    await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
    await _bgmPlayer.setVolume(0.55);
    if (!isMuted) {
      await _bgmPlayer.play(BytesSource(_bgmWav));
    }
  }

  Future<void> toggleMute() async {
    isMuted = !isMuted;
    if (isMuted) {
      await _bgmPlayer.pause();
    } else {
      await _bgmPlayer.resume();
    }
  }

  void playLaunch() => _playSfx(_launchSfxWav, 0.35);
  void playUpgrade() => _playSfx(_upgradeSfxWav, 0.6);
  void playCapture() => _playSfx(_captureSfxWav, 0.5);

  void _playSfx(Uint8List wavBytes, double volume) {
    if (isMuted || !_initialized) return;
    final player = _sfxPool[_sfxIndex];
    _sfxIndex = (_sfxIndex + 1) % _sfxPool.length;
    player.setVolume(volume);
    player.play(BytesSource(wavBytes));
  }

  void dispose() {
    _bgmPlayer.dispose();
    for (final p in _sfxPool) {
      p.dispose();
    }
  }

  Uint8List _generateSpaceAmbientWav({
    required double durationSec,
    int sampleRate = 22050,
  }) {
    final int numSamples = (durationSec * sampleRate).toInt();
    final ByteData data = ByteData(44 + numSamples * 2);
    _writeWavHeader(data, numSamples, sampleRate);

    final List<List<double>> chords = [
      [65.41, 130.81, 196.00, 246.94, 293.66, 329.63],
      [55.00, 110.00, 164.81, 220.00, 246.94, 329.63],
    ];

    final List<double> bellNotes = [
      523.25,
      587.33,
      659.25,
      783.99,
      987.77,
      1046.50,
      1318.51,
      1567.98
    ];

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double loopProgress = t / durationSec;
      final double chordBlend = 0.5 - 0.5 * cos(loopProgress * 2 * pi);
      final c1 = chords[0];
      final c2 = chords[1];

      double sample = 0.0;
      final double lfo = 0.75 + 0.25 * sin(2 * pi * (2.0 / durationSec) * t);
      for (int v = 0; v < c1.length; v++) {
        final double f1 = c1[v];
        final double f2 = c2[v];
        final double vAmp = v == 0 ? 0.22 : (0.11 / sqrt(v));
        final double wave1 =
            sin(2 * pi * f1 * t) + 0.5 * sin(2 * pi * (f1 * 1.002) * t + 0.8);
        final double wave2 =
            sin(2 * pi * f2 * t) + 0.5 * sin(2 * pi * (f2 * 1.002) * t + 1.7);
        sample += ((1.0 - chordBlend) * wave1 + chordBlend * wave2) * vAmp * lfo;
      }

      for (int b = 0; b < bellNotes.length; b++) {
        final double strikeTime = (b * (durationSec / bellNotes.length)) + 0.5;
        final double dtBell = t - strikeTime;
        if (dtBell > 0.0 && dtBell < 2.8) {
          final double bellEnv = exp(-dtBell * 2.2);
          final double f = bellNotes[b];
          sample += sin(2 * pi * f * dtBell) * bellEnv * 0.065;
          sample += sin(2 * pi * (f * 2.01) * dtBell) * bellEnv * 0.032;
        }
      }

      sample = sample.clamp(-1.0, 1.0);
      final int s16 = (sample * 32767.0).toInt();
      data.setInt16(44 + i * 2, s16, Endian.little);
    }

    return data.buffer.asUint8List();
  }

  Uint8List _generateChordChimeWav(
    List<double> frequencies, {
    required double durationSec,
    double volume = 0.5,
    bool arpeggio = false,
    int sampleRate = 22050,
  }) {
    final int numSamples = (durationSec * sampleRate).toInt();
    final ByteData data = ByteData(44 + numSamples * 2);
    _writeWavHeader(data, numSamples, sampleRate);

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      double sample = 0.0;

      for (int v = 0; v < frequencies.length; v++) {
        final double startDelay = arpeggio ? (v * 0.065) : 0.0;
        if (t < startDelay) continue;
        final double noteT = t - startDelay;
        final double env = exp(-noteT * (arpeggio ? 4.2 : 5.5));
        final double f = frequencies[v];
        final double wave = sin(2 * pi * f * noteT) +
            0.35 * sin(2 * pi * (f * 2.0) * noteT) +
            0.15 * sin(2 * pi * (f * 3.0) * noteT);
        sample += wave * env * (1.0 / frequencies.length);
      }

      sample = (sample * volume).clamp(-1.0, 1.0);
      final int s16 = (sample * 32767.0).toInt();
      data.setInt16(44 + i * 2, s16, Endian.little);
    }

    return data.buffer.asUint8List();
  }

  void _writeWavHeader(ByteData data, int numSamples, int sampleRate) {
    const int numChannels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int subChunk2Size = numSamples * numChannels * (bitsPerSample ~/ 8);
    final int chunkSize = 36 + subChunk2Size;

    data.setUint8(0, 0x52); // 'R'
    data.setUint8(1, 0x49); // 'I'
    data.setUint8(2, 0x46); // 'F'
    data.setUint8(3, 0x46); // 'F'
    data.setUint32(4, chunkSize, Endian.little);
    data.setUint8(8, 0x57); // 'W'
    data.setUint8(9, 0x41); // 'A'
    data.setUint8(10, 0x56); // 'V'
    data.setUint8(11, 0x45); // 'E'

    data.setUint8(12, 0x66); // 'f'
    data.setUint8(13, 0x6D); // 'm'
    data.setUint8(14, 0x74); // 't'
    data.setUint8(15, 0x20); // ' '
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);

    data.setUint8(36, 0x64); // 'd'
    data.setUint8(37, 0x61); // 'a'
    data.setUint8(38, 0x74); // 't'
    data.setUint8(39, 0x61); // 'a'
    data.setUint32(40, subChunk2Size, Endian.little);
  }
}

enum Faction { neutral, player, enemy1, enemy2 }

Color factionColor(Faction faction) {
  switch (faction) {
    case Faction.neutral:
      return const Color(0xFF6B7280);
    case Faction.player:
      return const Color(0xFF00E5FF);
    case Faction.enemy1:
      return const Color(0xFFFF1744);
    case Faction.enemy2:
      return const Color(0xFF00E676);
  }
}

enum GalaxyType {
  andromeda,
  labyrinth,
  singularity,
  deepSpace,
}

class GalaxyDefinition {
  final GalaxyType type;
  final String title;
  final String subtitle;
  final String description;
  final Color primaryColor;
  final IconData icon;
  final List<ConstellationType> constellations;

  const GalaxyDefinition({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.primaryColor,
    required this.icon,
    required this.constellations,
  });
}

enum ConstellationType {
  // Galaxy 1: Andromeda
  twinSpiral,
  ringCluster,
  binaryFront,
  supernovaCross,
  // Galaxy 2: Labyrinth
  mazeCorridors,
  citadelWalls,
  chamberMatrix,
  // Galaxy 3: Singularity
  wormholeGate,
  twinWormholes,
  singularityCrucible,
  // Galaxy 4: Deep Space
  labyrinthWormhole,
  pulsarOmega,
}

final List<GalaxyDefinition> galaxies = [
  const GalaxyDefinition(
    type: GalaxyType.andromeda,
    title: 'ГАЛАКТИКА АНДРОМЕДА',
    subtitle: 'Классические звёздные фронты',
    description: 'Спиральные рукава, двойные кольца орбит и симметричные звёздные скопления.',
    primaryColor: Color(0xFF00E5FF),
    icon: Icons.blur_circular,
    constellations: [
      ConstellationType.twinSpiral,
      ConstellationType.ringCluster,
      ConstellationType.binaryFront,
      ConstellationType.supernovaCross,
    ],
  ),
  const GalaxyDefinition(
    type: GalaxyType.labyrinth,
    title: 'ГАЛАКТИКА ЛАБИРИНТ',
    subtitle: 'Космические стены и коридоры',
    description: 'Лабиринты из энергобарьеров, защитные цитадели и изолированные шлюзы.',
    primaryColor: Color(0xFF76FF03),
    icon: Icons.grid_4x4,
    constellations: [
      ConstellationType.mazeCorridors,
      ConstellationType.citadelWalls,
      ConstellationType.chamberMatrix,
    ],
  ),
  const GalaxyDefinition(
    type: GalaxyType.singularity,
    title: 'ГАЛАКТИКА СИНГУЛЯРНОСТЬ',
    subtitle: 'Червоточины и полярные джеты',
    description: 'Накапливайте частицы в червоточинах и обрушивайте релятивистские потоки плазмы.',
    primaryColor: Color(0xFFE040FB),
    icon: Icons.cyclone,
    constellations: [
      ConstellationType.wormholeGate,
      ConstellationType.twinWormholes,
      ConstellationType.singularityCrucible,
    ],
  ),
  const GalaxyDefinition(
    type: GalaxyType.deepSpace,
    title: 'ГЛУБОКИЙ КОСМОС',
    subtitle: 'Атомные ядра и гипер-аномалии',
    description: 'Лабиринты с червоточинами и мощные звёзды 3+ уровня с перекрёстными атомными орбитами.',
    primaryColor: Color(0xFFFF9100),
    icon: Icons.all_inclusive,
    constellations: [
      ConstellationType.labyrinthWormhole,
      ConstellationType.pulsarOmega,
    ],
  ),
];

GalaxyDefinition galaxyForType(ConstellationType type) {
  for (final g in galaxies) {
    if (g.constellations.contains(type)) return g;
  }
  return galaxies[0];
}

String constellationTitle(ConstellationType type) {
  switch (type) {
    case ConstellationType.twinSpiral:
      return 'ANDROMEDA VORTEX';
    case ConstellationType.ringCluster:
      return 'ORION RING';
    case ConstellationType.binaryFront:
      return 'CYGNUS BINARY';
    case ConstellationType.supernovaCross:
      return 'PULSAR CROSS';
    case ConstellationType.mazeCorridors:
      return 'LABYRINTH NEXUS';
    case ConstellationType.citadelWalls:
      return 'CITADEL BARRIER';
    case ConstellationType.chamberMatrix:
      return 'CHAMBER MATRIX';
    case ConstellationType.wormholeGate:
      return 'SINGULARITY GATE';
    case ConstellationType.twinWormholes:
      return 'TWIN HORIZONS';
    case ConstellationType.singularityCrucible:
      return 'COSMIC CRUCIBLE';
    case ConstellationType.labyrinthWormhole:
      return 'ASTEROID CHASM';
    case ConstellationType.pulsarOmega:
      return 'PULSAR OMEGA';
  }
}

String constellationSubtitle(ConstellationType type) {
  switch (type) {
    case ConstellationType.twinSpiral:
      return 'Трёхрукавная вращающаяся спираль';
    case ConstellationType.ringCluster:
      return 'Двойное концентрическое кольцо орбит';
    case ConstellationType.binaryFront:
      return 'Симметричный бинарный фронт';
    case ConstellationType.supernovaCross:
      return 'Крестообразный пульсар с кластерами';
    case ConstellationType.mazeCorridors:
      return 'Лабиринт с защитными коридорами';
    case ConstellationType.citadelWalls:
      return 'Оборонительные стены и цитадели';
    case ConstellationType.chamberMatrix:
      return 'Четыре изолированных сектора';
    case ConstellationType.wormholeGate:
      return 'Центральная червоточина с джетами';
    case ConstellationType.twinWormholes:
      return 'Две червоточины с перекрёстными джетами';
    case ConstellationType.singularityCrucible:
      return 'Битва вокруг гипер-сингулярности';
    case ConstellationType.labyrinthWormhole:
      return 'Лабиринт из стен вокруг червоточины';
    case ConstellationType.pulsarOmega:
      return 'Звёзды 3+ уровня с атомными орбитами';
  }
}

class BgStar {
  Offset pos;
  double depth;
  double size;
  double phase;
  BgStar(this.pos, this.depth, this.size, this.phase);
}

class PlasmaCell {
  final double radialFactor;
  final double baseAngle;
  final double angularSpeed;
  final double sizeFactor;
  final double phase;
  final bool isBright;

  PlasmaCell({
    required this.radialFactor,
    required this.baseAngle,
    required this.angularSpeed,
    required this.sizeFactor,
    required this.phase,
    required this.isBright,
  });
}

class StarNode {
  final int id;
  Offset pos;
  Faction owner;
  int level; // 1..4
  final int maxLevel;
  double hp;
  int investedUnits;
  double pulsePhase;
  double spawnAccumulator;
  double orbitRadius;
  double orbitSpeed;
  double orbitAngle;
  Offset? orbitCenter;
  final List<PlasmaCell> plasmaCells;

  StarNode({
    required this.id,
    required this.pos,
    required this.owner,
    this.level = 1,
    this.maxLevel = 4,
    this.hp = 100.0,
    this.investedUnits = 0,
    required this.pulsePhase,
    this.spawnAccumulator = 0.0,
    this.orbitCenter,
    this.orbitRadius = 0.0,
    this.orbitSpeed = 0.0,
    this.orbitAngle = 0.0,
    required this.plasmaCells,
  });

  double get radius {
    if (owner == Faction.neutral) return 22.0;
    switch (level) {
      case 1:
        return 24.0;
      case 2:
        return 32.0;
      case 3:
        return 40.0;
      case 4:
      default:
        return 48.0;
    }
  }

  int get upgradeCost {
    switch (level) {
      case 1:
        return 30;
      case 2:
        return 65;
      case 3:
        return 110;
      default:
        return 999999;
    }
  }

  double get productionRate =>
      owner == Faction.neutral ? 0.0 : (0.35 + level * 0.45);

  Map<String, dynamic> toJson() => {
        'id': id,
        'dx': pos.dx,
        'dy': pos.dy,
        'owner': owner.index,
        'level': level,
        'hp': hp,
        'investedUnits': investedUnits,
        'pulsePhase': pulsePhase,
        'spawnAccumulator': spawnAccumulator,
        'orbitRadius': orbitRadius,
        'orbitSpeed': orbitSpeed,
        'orbitAngle': orbitAngle,
        'hasOrbitCenter': orbitCenter != null,
        'orbitCenterDx': orbitCenter?.dx ?? 0.0,
        'orbitCenterDy': orbitCenter?.dy ?? 0.0,
      };

  factory StarNode.fromJson(
      Map<String, dynamic> json, List<PlasmaCell> plasma) {
    final bool hasCenter = json['hasOrbitCenter'] as bool? ?? false;
    return StarNode(
      id: json['id'] as int,
      pos: Offset(
        (json['dx'] as num).toDouble(),
        (json['dy'] as num).toDouble(),
      ),
      owner: Faction.values[json['owner'] as int],
      level: json['level'] as int,
      hp: (json['hp'] as num).toDouble(),
      investedUnits: json['investedUnits'] as int? ?? 0,
      pulsePhase: (json['pulsePhase'] as num).toDouble(),
      spawnAccumulator: (json['spawnAccumulator'] as num?)?.toDouble() ?? 0.0,
      orbitCenter: hasCenter
          ? Offset(
              (json['orbitCenterDx'] as num).toDouble(),
              (json['orbitCenterDy'] as num).toDouble(),
            )
          : null,
      orbitRadius: (json['orbitRadius'] as num).toDouble(),
      orbitSpeed: (json['orbitSpeed'] as num).toDouble(),
      orbitAngle: (json['orbitAngle'] as num).toDouble(),
      plasmaCells: plasma,
    );
  }
}

class RendezvousPoint {
  final int id;
  Offset pos;
  Faction faction;
  double pulse;
  RendezvousPoint(this.id, this.pos, this.faction, {this.pulse = 0.0});

  Map<String, dynamic> toJson() => {
        'id': id,
        'dx': pos.dx,
        'dy': pos.dy,
        'faction': faction.index,
        'pulse': pulse,
      };

  factory RendezvousPoint.fromJson(Map<String, dynamic> json) {
    return RendezvousPoint(
      json['id'] as int,
      Offset(
        (json['dx'] as num).toDouble(),
        (json['dy'] as num).toDouble(),
      ),
      Faction.values[json['faction'] as int],
      pulse: (json['pulse'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ObstacleWall {
  final int id;
  final Offset start;
  final Offset end;
  final double thickness;
  final Color? glowColor;

  ObstacleWall({
    required this.id,
    required this.start,
    required this.end,
    this.thickness = 16.0,
    this.glowColor,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sx': start.dx,
        'sy': start.dy,
        'ex': end.dx,
        'ey': end.dy,
        'th': thickness,
        'color': glowColor?.toARGB32(),
      };

  factory ObstacleWall.fromJson(Map<String, dynamic> json) {
    final int? colorVal = json['color'] as int?;
    return ObstacleWall(
      id: json['id'] as int? ?? 0,
      start: Offset(
          (json['sx'] as num).toDouble(), (json['sy'] as num).toDouble()),
      end: Offset(
          (json['ex'] as num).toDouble(), (json['ey'] as num).toDouble()),
      thickness: (json['th'] as num?)?.toDouble() ?? 16.0,
      glowColor: colorVal != null ? Color(colorVal) : null,
    );
  }
}

class Wormhole {
  final int id;
  Offset pos;
  final double radius;
  final int criticalMass;
  int storedUnits;
  Faction lastAbsorbedFaction;
  final Map<Faction, int> factionContributions;
  double poleAngle;
  bool isErupting;
  double eruptionTimer;
  final double eruptionDuration;
  double jetAccumulator;
  double spinPhase;
  double pulsePhase;

  Wormhole({
    required this.id,
    required this.pos,
    this.radius = 36.0,
    this.criticalMass = 30,
    this.storedUnits = 0,
    this.lastAbsorbedFaction = Faction.neutral,
    Map<Faction, int>? factionContributions,
    this.poleAngle = 0.0,
    this.isErupting = false,
    this.eruptionTimer = 0.0,
    this.eruptionDuration = 3.5,
    this.jetAccumulator = 0.0,
    this.spinPhase = 0.0,
    this.pulsePhase = 0.0,
  }) : factionContributions = factionContributions ??
            {
              Faction.player: 0,
              Faction.enemy1: 0,
              Faction.enemy2: 0,
            };

  Map<String, dynamic> toJson() => {
        'id': id,
        'dx': pos.dx,
        'dy': pos.dy,
        'r': radius,
        'cm': criticalMass,
        'stored': storedUnits,
        'lastFaction': lastAbsorbedFaction.index,
        'contr': factionContributions
            .map((k, v) => MapEntry(k.index.toString(), v)),
        'poleAng': poleAngle,
        'isErupting': isErupting,
        'erTimer': eruptionTimer,
        'erDur': eruptionDuration,
        'spin': spinPhase,
        'pulse': pulsePhase,
      };

  factory Wormhole.fromJson(Map<String, dynamic> json) {
    final contrRaw = json['contr'] as Map<String, dynamic>?;
    final Map<Faction, int> contr = {
      Faction.player: 0,
      Faction.enemy1: 0,
      Faction.enemy2: 0,
    };
    if (contrRaw != null) {
      contrRaw.forEach((k, v) {
        final fIdx = int.tryParse(k);
        if (fIdx != null && fIdx >= 0 && fIdx < Faction.values.length) {
          contr[Faction.values[fIdx]] = (v as num).toInt();
        }
      });
    }

    final int? lfIdx = json['lastFaction'] as int?;
    return Wormhole(
      id: json['id'] as int,
      pos: Offset(
          (json['dx'] as num).toDouble(), (json['dy'] as num).toDouble()),
      radius: (json['r'] as num?)?.toDouble() ?? 36.0,
      criticalMass: json['cm'] as int? ?? 30,
      storedUnits: json['stored'] as int? ?? 0,
      lastAbsorbedFaction:
          lfIdx != null ? Faction.values[lfIdx] : Faction.neutral,
      factionContributions: contr,
      poleAngle: (json['poleAng'] as num?)?.toDouble() ?? 0.0,
      isErupting: json['isErupting'] as bool? ?? false,
      eruptionTimer: (json['erTimer'] as num?)?.toDouble() ?? 0.0,
      eruptionDuration: (json['erDur'] as num?)?.toDouble() ?? 3.5,
      spinPhase: (json['spin'] as num?)?.toDouble() ?? 0.0,
      pulsePhase: (json['pulse'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SwarmUnit {
  Offset pos;
  Offset vel;
  Faction faction;
  StarNode? targetNode;
  RendezvousPoint? targetRendezvous;
  Wormhole? targetWormhole;
  bool isOrbiting;
  bool isUpgradingTarget;
  double orbitAngle;
  double orbitDist;
  double speed;
  double phase;
  bool dead = false;

  SwarmUnit({
    required this.pos,
    required this.vel,
    required this.faction,
    this.targetNode,
    this.targetRendezvous,
    this.targetWormhole,
    this.isOrbiting = true,
    this.isUpgradingTarget = false,
    required this.orbitAngle,
    required this.orbitDist,
    required this.speed,
    required this.phase,
  });

  Map<String, dynamic> toJson() => {
        'dx': pos.dx,
        'dy': pos.dy,
        'vdx': vel.dx,
        'vdy': vel.dy,
        'faction': faction.index,
        'targetNodeId': targetNode?.id,
        'targetRvId': targetRendezvous?.id,
        'targetWhId': targetWormhole?.id,
        'isOrbiting': isOrbiting,
        'isUpgradingTarget': isUpgradingTarget,
        'orbitAngle': orbitAngle,
        'orbitDist': orbitDist,
        'speed': speed,
        'phase': phase,
      };

  factory SwarmUnit.fromJson(
    Map<String, dynamic> json,
    Map<int, StarNode> nodeMap,
    Map<int, RendezvousPoint> rvMap,
    Map<int, Wormhole> whMap,
  ) {
    final int? tNodeId = json['targetNodeId'] as int?;
    final int? tRvId = json['targetRvId'] as int?;
    final int? tWhId = json['targetWhId'] as int?;
    return SwarmUnit(
      pos: Offset(
        (json['dx'] as num).toDouble(),
        (json['dy'] as num).toDouble(),
      ),
      vel: Offset(
        (json['vdx'] as num).toDouble(),
        (json['vdy'] as num).toDouble(),
      ),
      faction: Faction.values[json['faction'] as int],
      targetNode: tNodeId != null ? nodeMap[tNodeId] : null,
      targetRendezvous: tRvId != null ? rvMap[tRvId] : null,
      targetWormhole: tWhId != null ? whMap[tWhId] : null,
      isOrbiting: json['isOrbiting'] as bool? ?? true,
      isUpgradingTarget: json['isUpgradingTarget'] as bool? ?? false,
      orbitAngle: (json['orbitAngle'] as num).toDouble(),
      orbitDist: (json['orbitDist'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      phase: (json['phase'] as num).toDouble(),
    );
  }
}

class SparkParticle {
  Offset pos;
  Offset vel;
  Color color;
  double life;
  double maxLife;
  double size;

  SparkParticle({
    required this.pos,
    required this.vel,
    required this.color,
    required this.life,
    required this.size,
  }) : maxLife = life;
}

class PulseWave {
  Offset pos;
  Color color;
  double radius;
  double maxRadius;
  double life;

  PulseWave({
    required this.pos,
    required this.color,
    required this.maxRadius,
    this.radius = 4.0,
    this.life = 1.0,
  });
}

class FloatingText {
  Offset pos;
  String text;
  Color color;
  double life;

  FloatingText({
    required this.pos,
    required this.text,
    required this.color,
    this.life = 1.0,
  });
}

class ConstellationSaveData {
  final ConstellationType type;
  final List<StarNode> nodes;
  final List<RendezvousPoint> rendezvousPoints;
  final List<SwarmUnit> units;
  final List<ObstacleWall> obstacles;
  final List<Wormhole> wormholes;
  final Faction? winner;
  final Offset cameraOffset;
  final double cameraZoom;
  final bool isStarted;

  ConstellationSaveData({
    required this.type,
    required this.nodes,
    required this.rendezvousPoints,
    required this.units,
    this.obstacles = const [],
    this.wormholes = const [],
    required this.winner,
    required this.cameraOffset,
    required this.cameraZoom,
    required this.isStarted,
  });

  int countUnits(Faction f) =>
      units.where((u) => !u.dead && u.faction == f).length;

  int countNodes(Faction f) => nodes.where((n) => n.owner == f).length;

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'rv': rendezvousPoints.map((r) => r.toJson()).toList(),
        'units': units.where((u) => !u.dead).map((u) => u.toJson()).toList(),
        'obs': obstacles.map((o) => o.toJson()).toList(),
        'wh': wormholes.map((w) => w.toJson()).toList(),
        'winner': winner?.index,
        'camDx': cameraOffset.dx,
        'camDy': cameraOffset.dy,
        'camZoom': cameraZoom,
        'isStarted': isStarted,
      };

  factory ConstellationSaveData.fromJson(
    Map<String, dynamic> json,
    List<PlasmaCell> Function() generatePlasma,
  ) {
    final type = ConstellationType.values[json['type'] as int];
    final nodesList = (json['nodes'] as List)
        .map((n) =>
            StarNode.fromJson(n as Map<String, dynamic>, generatePlasma()))
        .toList();
    final nodeMap = {for (final n in nodesList) n.id: n};

    final rvList = (json['rv'] as List)
        .map((r) => RendezvousPoint.fromJson(r as Map<String, dynamic>))
        .toList();
    final rvMap = {for (final r in rvList) r.id: r};

    final whList = (json['wh'] as List? ?? [])
        .map((w) => Wormhole.fromJson(w as Map<String, dynamic>))
        .toList();
    final whMap = {for (final w in whList) w.id: w};

    final obsList = (json['obs'] as List? ?? [])
        .map((o) => ObstacleWall.fromJson(o as Map<String, dynamic>))
        .toList();

    final unitsList = (json['units'] as List)
        .map((u) =>
            SwarmUnit.fromJson(u as Map<String, dynamic>, nodeMap, rvMap, whMap))
        .toList();

    final int? winnerIdx = json['winner'] as int?;

    return ConstellationSaveData(
      type: type,
      nodes: nodesList,
      rendezvousPoints: rvList,
      units: unitsList,
      obstacles: obsList,
      wormholes: whList,
      winner: winnerIdx != null ? Faction.values[winnerIdx] : null,
      cameraOffset: Offset(
        (json['camDx'] as num?)?.toDouble() ?? 0.0,
        (json['camDy'] as num?)?.toDouble() ?? 0.0,
      ),
      cameraZoom: (json['camZoom'] as num?)?.toDouble() ?? 0.65,
      isStarted: json['isStarted'] as bool? ?? true,
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _lastTime = Duration.zero;
  double _globalTime = 0.0;
  double _autoSaveTimer = 0.0;

  final CosmicAudioEngine _audio = CosmicAudioEngine();
  final Random _rng = Random(42);

  final List<BgStar> _bgStars = [];
  final List<StarNode> _nodes = [];
  final List<SwarmUnit> _units = [];
  final List<ObstacleWall> _obstacles = [];
  final List<Wormhole> _wormholes = [];
  final List<SparkParticle> _sparks = [];
  final List<PulseWave> _waves = [];
  final List<FloatingText> _floatingTexts = [];
  final List<RendezvousPoint> _rendezvousPoints = [];
  int _rvIdCounter = 1;

  final Set<StarNode> _selectedNodes = {};
  final Set<RendezvousPoint> _selectedRendezvous = {};
  final Set<SwarmUnit> _selectedUnits = {};

  Offset? _selectionBoxStartWorld;
  Offset? _selectionBoxCurrentWorld;

  Offset _cameraOffset = Offset.zero;
  double _cameraZoom = 0.65;
  final Map<int, Offset> _activePointers = {};
  Offset? _lastPinchFocal;
  double? _lastPinchDist;

  int? _primaryPointerId;
  Offset? _pointerDownScreenPos;
  bool _isBoxSelecting = false;
  bool _gestureWasMultitouch = false;

  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
  StarNode? _lastTappedNode;

  // Меню и навигация: выбор галактики -> выбор созвездия
  bool _inMenu = true;
  GalaxyType? _selectedGalaxy;
  late PageController _galaxyPageController;
  int _galaxyPageIndex = 0;
  double _galaxyPageValue = 0.0;

  late PageController _constellationPageController;
  int _constellationPageIndex = 0;
  double _constellationPageValue = 0.0;

  final Map<ConstellationType, ConstellationSaveData> _savedConstellations = {};

  ConstellationType _currentMapType = ConstellationType.twinSpiral;
  String _mapName = 'ANDROMEDA VORTEX';
  double _aiTimer = 0.0;
  double _gameSpeed = 1.0;
  bool _isPaused = false;
  Faction? _winner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _galaxyPageController =
        PageController(viewportFraction: 0.74, initialPage: 0);
    _galaxyPageController.addListener(() {
      if (_galaxyPageController.hasClients &&
          _galaxyPageController.page != null) {
        setState(() {
          _galaxyPageValue = _galaxyPageController.page!;
        });
      }
    });

    _constellationPageController =
        PageController(viewportFraction: 0.68, initialPage: 0);
    _constellationPageController.addListener(() {
      if (_constellationPageController.hasClients &&
          _constellationPageController.page != null) {
        setState(() {
          _constellationPageValue = _constellationPageController.page!;
        });
      }
    });

    _initBackground();
    _initDefaultPreviews();
    _loadPersistentState();
    _audio.init();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _galaxyPageController.dispose();
    _constellationPageController.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_inMenu && _winner == null) {
        _saveCurrentLevelSnapshot();
        _persistStateToDisk();
      }
    }
  }

  Future<File?> _getSaveFile() async {
    final candidateDirs = <String>[
      if (Platform.isAndroid) '/data/user/0/com.sargis.auralux/files',
      '${Platform.environment['HOME']}/.local/share/auralux_clone',
      '/tmp/auralux_clone_data',
    ];

    for (final dirPath in candidateDirs) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return File('${dir.path}/auralux_galaxies_save_v2.json');
      } catch (_) {}
    }
    return null;
  }

  void _initDefaultPreviews() {
    for (final type in ConstellationType.values) {
      _savedConstellations[type] = _buildInitialConstellationData(type);
    }
  }

  Future<void> _loadPersistentState() async {
    try {
      final file = await _getSaveFile();
      if (file == null || !await file.exists()) return;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      final Map<String, dynamic> root =
          jsonDecode(content) as Map<String, dynamic>;
      final levelsMap = root['levels'] as Map<String, dynamic>?;
      if (levelsMap != null) {
        for (final entry in levelsMap.entries) {
          final idx = int.tryParse(entry.key);
          if (idx != null &&
              idx >= 0 &&
              idx < ConstellationType.values.length) {
            final cType = ConstellationType.values[idx];
            _savedConstellations[cType] = ConstellationSaveData.fromJson(
              entry.value as Map<String, dynamic>,
              _generatePlasmaTexture,
            );
          }
        }
      }
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _persistStateToDisk() async {
    try {
      final file = await _getSaveFile();
      if (file == null) return;

      final Map<String, dynamic> levelsJson = {};
      for (final entry in _savedConstellations.entries) {
        if (entry.value.isStarted) {
          levelsJson[entry.key.index.toString()] = entry.value.toJson();
        }
      }

      final payload = jsonEncode({
        'version': 2,
        'levels': levelsJson,
      });
      await file.writeAsString(payload, flush: true);
    } catch (_) {}
  }

  void _saveCurrentLevelSnapshot() {
    final clonedNodes = _nodes
        .map((n) => StarNode.fromJson(n.toJson(), _generatePlasmaTexture()))
        .toList();
    final nodeMap = {for (final n in clonedNodes) n.id: n};

    final clonedRv = _rendezvousPoints
        .map((r) => RendezvousPoint.fromJson(r.toJson()))
        .toList();
    final rvMap = {for (final r in clonedRv) r.id: r};

    final clonedWormholes =
        _wormholes.map((w) => Wormhole.fromJson(w.toJson())).toList();
    final whMap = {for (final w in clonedWormholes) w.id: w};

    final clonedUnits = _units
        .where((u) => !u.dead)
        .map((u) => SwarmUnit.fromJson(u.toJson(), nodeMap, rvMap, whMap))
        .toList();

    final clonedObstacles =
        _obstacles.map((o) => ObstacleWall.fromJson(o.toJson())).toList();

    _savedConstellations[_currentMapType] = ConstellationSaveData(
      type: _currentMapType,
      nodes: clonedNodes,
      rendezvousPoints: clonedRv,
      units: clonedUnits,
      obstacles: clonedObstacles,
      wormholes: clonedWormholes,
      winner: _winner,
      cameraOffset: _cameraOffset,
      cameraZoom: _cameraZoom,
      isStarted: true,
    );
  }

  void _openConstellationFromMenu(ConstellationType type,
      {bool forceRestart = false}) {
    _currentMapType = type;
    _mapName = constellationTitle(type);
    _isPaused = false;

    if (forceRestart ||
        !_savedConstellations.containsKey(type) ||
        !_savedConstellations[type]!.isStarted) {
      final fresh = _buildInitialConstellationData(type, markStarted: true);
      _savedConstellations[type] = fresh;
      _applySaveDataToActiveWorld(fresh);
    } else {
      _applySaveDataToActiveWorld(_savedConstellations[type]!);
    }

    _inMenu = false;
    _persistStateToDisk();
    setState(() {});
  }

  void _returnToMenu() {
    _saveCurrentLevelSnapshot();
    _persistStateToDisk();
    _clearSelection();
    _isBoxSelecting = false;
    _inMenu = true;
    _selectedGalaxy = galaxyForType(_currentMapType).type;
    setState(() {});
  }

  void _applySaveDataToActiveWorld(ConstellationSaveData data) {
    _nodes.clear();
    _units.clear();
    _sparks.clear();
    _waves.clear();
    _floatingTexts.clear();
    _rendezvousPoints.clear();
    _obstacles.clear();
    _wormholes.clear();
    _clearSelection();

    _nodes.addAll(data.nodes);
    _rendezvousPoints.addAll(data.rendezvousPoints);
    _units.addAll(data.units);
    _obstacles.addAll(data.obstacles);
    _wormholes.addAll(data.wormholes.map((w) => Wormhole.fromJson(w.toJson())));
    _winner = data.winner;
    _cameraOffset = data.cameraOffset;
    _cameraZoom = data.cameraZoom;
  }

  void _clearSelection() {
    _selectedNodes.clear();
    _selectedRendezvous.clear();
    _selectedUnits.clear();
  }

  bool get _hasAnySelection =>
      _selectedNodes.isNotEmpty ||
      _selectedRendezvous.isNotEmpty ||
      _selectedUnits.isNotEmpty;

  void _initBackground() {
    _bgStars.clear();
    for (int i = 0; i < 280; i++) {
      final pos = Offset(
        (_rng.nextDouble() - 0.5) * 3600,
        (_rng.nextDouble() - 0.5) * 2400,
      );
      final depth = 0.2 + _rng.nextDouble() * 0.8;
      final size = 0.8 + _rng.nextDouble() * 2.2;
      final phase = _rng.nextDouble() * pi * 2;
      _bgStars.add(BgStar(pos, depth, size, phase));
    }
  }

  List<PlasmaCell> _generatePlasmaTexture() {
    final List<PlasmaCell> cells = [];
    const int count = 28;
    for (int i = 0; i < count; i++) {
      cells.add(
        PlasmaCell(
          radialFactor: 0.15 + _rng.nextDouble() * 0.8,
          baseAngle: _rng.nextDouble() * pi * 2,
          angularSpeed:
              (0.35 + _rng.nextDouble() * 0.85) * (_rng.nextBool() ? 1 : -1),
          sizeFactor: 0.18 + _rng.nextDouble() * 0.28,
          phase: _rng.nextDouble() * pi * 2,
          isBright: _rng.nextDouble() < 0.45,
        ),
      );
    }
    return cells;
  }

  ConstellationSaveData _buildInitialConstellationData(
    ConstellationType type, {
    bool markStarted = false,
  }) {
    int idCounter = 1;
    int wallIdCounter = 1;
    int whIdCounter = 1;
    final List<StarNode> genNodes = [];
    final List<SwarmUnit> genUnits = [];
    final List<ObstacleWall> genWalls = [];
    final List<Wormhole> genWormholes = [];

    void spawnInitialUnits(StarNode node, Faction faction, int count) {
      for (int i = 0; i < count; i++) {
        double ang = _rng.nextDouble() * pi * 2;
        double dist = node.radius + 14.0 + _rng.nextDouble() * 30.0;
        Offset pos = node.pos + Offset(cos(ang) * dist, sin(ang) * dist);
        genUnits.add(
          SwarmUnit(
            pos: pos,
            vel: Offset.zero,
            faction: faction,
            targetNode: node,
            isOrbiting: true,
            isUpgradingTarget: false,
            orbitAngle: ang,
            orbitDist: dist,
            speed: 95.0 + _rng.nextDouble() * 30.0,
            phase: _rng.nextDouble() * pi * 2,
          ),
        );
      }
    }

    void addNode(
      Offset pos,
      Faction owner, {
      int level = 1,
      double hp = 100.0,
      Offset? orbitCenter,
      double orbitRadius = 0.0,
      double orbitSpeed = 0.0,
      double orbitAngle = 0.0,
      int startingUnits = 24,
    }) {
      final node = StarNode(
        id: idCounter++,
        pos: pos,
        owner: owner,
        level: owner == Faction.neutral ? 0 : level,
        hp: owner == Faction.neutral ? (35.0 + _rng.nextInt(40).toDouble()) : hp,
        pulsePhase: _rng.nextDouble() * pi * 2,
        orbitCenter: orbitCenter,
        orbitRadius: orbitRadius,
        orbitSpeed: orbitSpeed,
        orbitAngle: orbitAngle,
        plasmaCells: _generatePlasmaTexture(),
      );
      genNodes.add(node);

      if (owner != Faction.neutral) {
        spawnInitialUnits(node, owner, startingUnits);
      }
    }

    void addWall(Offset start, Offset end, {double thickness = 16.0, Color? glow}) {
      genWalls.add(ObstacleWall(
        id: wallIdCounter++,
        start: start,
        end: end,
        thickness: thickness,
        glowColor: glow,
      ));
    }

    void addWormhole(Offset pos, {double radius = 38.0, int criticalMass = 30, double poleAngle = 0.0}) {
      genWormholes.add(Wormhole(
        id: whIdCounter++,
        pos: pos,
        radius: radius,
        criticalMass: criticalMass,
        poleAngle: poleAngle,
      ));
    }

    switch (type) {
      // 1. ANDROMEDA VORTEX
      case ConstellationType.twinSpiral:
        addNode(Offset.zero, Faction.neutral, level: 0, hp: 90);
        const int arms = 3;
        const int nodesPerArm = 4;
        for (int a = 0; a < arms; a++) {
          double baseAngle = (2 * pi / arms) * a;
          for (int i = 1; i <= nodesPerArm; i++) {
            double dist = i * 160.0;
            double angle = baseAngle + i * 0.52;
            Offset pos = Offset(cos(angle) * dist, sin(angle) * dist);

            Faction owner = Faction.neutral;
            if (i == nodesPerArm) {
              if (a == 0) owner = Faction.player;
              if (a == 1) owner = Faction.enemy1;
              if (a == 2) owner = Faction.enemy2;
            }

            addNode(
              pos,
              owner,
              level: owner == Faction.neutral ? 0 : 1,
              orbitCenter: Offset.zero,
              orbitRadius: dist,
              orbitSpeed: (i % 2 == 0 ? 1 : -1) * (0.025 / i),
              orbitAngle: angle,
            );
          }
        }
        break;

      // 2. ORION RING
      case ConstellationType.ringCluster:
        addNode(Offset.zero, Faction.neutral, level: 0, hp: 85);
        for (int i = 0; i < 6; i++) {
          double ang = (2 * pi / 6) * i;
          double r = 220.0;
          addNode(
            Offset(cos(ang) * r, sin(ang) * r),
            Faction.neutral,
            orbitCenter: Offset.zero,
            orbitRadius: r,
            orbitSpeed: 0.035,
            orbitAngle: ang,
          );
        }
        for (int i = 0; i < 9; i++) {
          double ang = (2 * pi / 9) * i;
          double r = 470.0;
          Faction f = Faction.neutral;
          if (i == 0) f = Faction.player;
          if (i == 3) f = Faction.enemy1;
          if (i == 6) f = Faction.enemy2;

          addNode(
            Offset(cos(ang) * r, sin(ang) * r),
            f,
            orbitCenter: Offset.zero,
            orbitRadius: r,
            orbitSpeed: -0.018,
            orbitAngle: ang,
          );
        }
        break;

      // 3. CYGNUS BINARY
      case ConstellationType.binaryFront:
        addNode(const Offset(0, -150), Faction.neutral, hp: 50);
        addNode(const Offset(0, 150), Faction.neutral, hp: 50);
        addNode(Offset.zero, Faction.neutral, hp: 95);

        final List<Offset> leftCluster = [
          const Offset(-520, 0),
          const Offset(-360, -200),
          const Offset(-360, 200),
          const Offset(-220, -90),
          const Offset(-220, 90),
          const Offset(-540, -280),
          const Offset(-540, 280),
        ];

        for (int i = 0; i < leftCluster.length; i++) {
          final p = leftCluster[i];
          addNode(p, i == 0 ? Faction.player : Faction.neutral);
          addNode(
            Offset(-p.dx, p.dy),
            i == 0
                ? Faction.enemy1
                : (i == 5 ? Faction.enemy2 : Faction.neutral),
          );
        }
        break;

      // 4. CRUX SUPERNOVA
      case ConstellationType.supernovaCross:
        addNode(Offset.zero, Faction.neutral, hp: 100);
        for (int dir = 0; dir < 4; dir++) {
          double ang = dir * (pi / 2);
          for (int step = 1; step <= 3; step++) {
            double r = step * 190.0;
            Offset pos = Offset(cos(ang) * r, sin(ang) * r);
            Faction f = Faction.neutral;
            if (step == 3) {
              if (dir == 0) f = Faction.player;
              if (dir == 1) f = Faction.enemy1;
              if (dir == 2) f = Faction.enemy2;
            }
            addNode(pos, f);

            if (step == 2) {
              double sideAng1 = ang + 0.42;
              double sideAng2 = ang - 0.42;
              addNode(
                Offset(cos(sideAng1) * (r + 60), sin(sideAng1) * (r + 60)),
                Faction.neutral,
              );
              addNode(
                Offset(cos(sideAng2) * (r + 60), sin(sideAng2) * (r + 60)),
                Faction.neutral,
              );
            }
          }
        }
        break;

      // 5. LABYRINTH NEXUS (Лабиринт с защитными коридорами)
      case ConstellationType.mazeCorridors:
        addNode(const Offset(-500, 0), Faction.player, level: 1, startingUnits: 28);
        addNode(const Offset(450, -260), Faction.enemy1, level: 1, startingUnits: 26);
        addNode(const Offset(450, 260), Faction.enemy2, level: 1, startingUnits: 26);

        addNode(Offset.zero, Faction.neutral, level: 0, hp: 90);
        addNode(const Offset(-220, -180), Faction.neutral);
        addNode(const Offset(-220, 180), Faction.neutral);
        addNode(const Offset(160, -140), Faction.neutral);
        addNode(const Offset(160, 140), Faction.neutral);
        addNode(const Offset(0, -320), Faction.neutral);
        addNode(const Offset(0, 320), Faction.neutral);

        // Стены лабиринта
        addWall(const Offset(-100, -420), const Offset(-100, -120), thickness: 18);
        addWall(const Offset(-100, 120), const Offset(-100, 420), thickness: 18);
        addWall(const Offset(-100, -200), const Offset(240, -200), thickness: 16);
        addWall(const Offset(-100, 200), const Offset(240, 200), thickness: 16);
        addWall(const Offset(240, -60), const Offset(520, 0), thickness: 16);
        addWall(const Offset(240, 60), const Offset(520, 0), thickness: 16);
        break;

      // 6. CITADEL BARRIER (Оборонительные цитадели и стены)
      case ConstellationType.citadelWalls:
        addNode(const Offset(-460, -220), Faction.player, level: 1);
        addNode(const Offset(460, -220), Faction.enemy1, level: 1);
        addNode(const Offset(0, 340), Faction.enemy2, level: 1);

        addNode(const Offset(-90, 0), Faction.neutral, hp: 80);
        addNode(const Offset(90, 0), Faction.neutral, hp: 80);
        addNode(const Offset(-280, 80), Faction.neutral);
        addNode(const Offset(280, 80), Faction.neutral);
        addNode(const Offset(0, -240), Faction.neutral);

        // Шестиугольный щит вокруг центральной цитадели с тремя проходами
        addWall(const Offset(-180, -90), const Offset(0, -190), thickness: 16);
        addWall(const Offset(180, -90), const Offset(0, -190), thickness: 16);
        addWall(const Offset(-220, 20), const Offset(-140, 160), thickness: 16);
        addWall(const Offset(220, 20), const Offset(140, 160), thickness: 16);
        addWall(const Offset(-70, 200), const Offset(70, 200), thickness: 16);

        // Внешние защитные барьеры
        addWall(const Offset(-380, -60), const Offset(-380, 180), thickness: 16);
        addWall(const Offset(380, -60), const Offset(380, 180), thickness: 16);
        break;

      // 7. CHAMBER MATRIX (Четыре изолированные камеры)
      case ConstellationType.chamberMatrix:
        addNode(const Offset(-380, -260), Faction.player, level: 1);
        addNode(const Offset(380, -260), Faction.enemy1, level: 1);
        addNode(const Offset(380, 260), Faction.enemy2, level: 1);

        // Нейтральная богатая камера (юго-запад)
        addNode(const Offset(-380, 260), Faction.neutral, hp: 70);
        addNode(const Offset(-240, 360), Faction.neutral, hp: 60);

        // Внутренние звёзды в камерах
        addNode(const Offset(-240, -360), Faction.neutral);
        addNode(const Offset(240, -360), Faction.neutral);
        addNode(const Offset(240, 360), Faction.neutral);

        // Центральная площадь
        addNode(Offset.zero, Faction.neutral, hp: 95);

        // Крестообразные стены с открытыми шлюзами
        addWall(const Offset(-580, 0), const Offset(-110, 0), thickness: 18);
        addWall(const Offset(110, 0), const Offset(580, 0), thickness: 18);
        addWall(const Offset(0, -450), const Offset(0, -110), thickness: 18);
        addWall(const Offset(0, 110), const Offset(0, 450), thickness: 18);
        break;

      // 8. SINGULARITY GATE (Центральная червоточина с полярными джетами)
      case ConstellationType.wormholeGate:
        addWormhole(Offset.zero, radius: 42.0, criticalMass: 30, poleAngle: pi / 2);

        addNode(const Offset(-500, 0), Faction.player, level: 1, startingUnits: 28);
        addNode(const Offset(500, 0), Faction.enemy1, level: 1, startingUnits: 28);

        // Звёзды на пути полярных джетов (север и юг)
        addNode(const Offset(0, -330), Faction.neutral, hp: 85);
        addNode(const Offset(0, 330), Faction.neutral, hp: 85);

        // Фланговые вспомогательные звёзды
        addNode(const Offset(-240, -180), Faction.neutral);
        addNode(const Offset(-240, 180), Faction.neutral);
        addNode(const Offset(240, -180), Faction.neutral);
        addNode(const Offset(240, 180), Faction.neutral);
        break;

      // 9. TWIN HORIZONS (Две червоточины с перекрёстными джетами)
      case ConstellationType.twinWormholes:
        addWormhole(const Offset(-190, 0), radius: 36.0, criticalMass: 25, poleAngle: -pi / 4);
        addWormhole(const Offset(190, 0), radius: 36.0, criticalMass: 25, poleAngle: pi / 4);

        addNode(const Offset(0, -380), Faction.player, level: 1, startingUnits: 28);
        addNode(const Offset(-460, 240), Faction.enemy1, level: 1, startingUnits: 26);
        addNode(const Offset(460, 240), Faction.enemy2, level: 1, startingUnits: 26);

        addNode(const Offset(0, 80), Faction.neutral, hp: 85);
        addNode(const Offset(-320, -120), Faction.neutral);
        addNode(const Offset(320, -120), Faction.neutral);
        addNode(const Offset(0, 340), Faction.neutral);
        break;

      // 10. COSMIC CRUCIBLE (Гипер-сингулярность в центре)
      case ConstellationType.singularityCrucible:
        addWormhole(Offset.zero, radius: 48.0, criticalMass: 40, poleAngle: 0.0);

        addNode(const Offset(-520, 0), Faction.player, level: 1, startingUnits: 32);
        addNode(const Offset(260, -450), Faction.enemy1, level: 1, startingUnits: 30);
        addNode(const Offset(260, 450), Faction.enemy2, level: 1, startingUnits: 30);

        // Внутреннее кольцо звёзд вокруг сингулярности
        for (int i = 0; i < 4; i++) {
          double ang = (pi / 2) * i + (pi / 4);
          addNode(
            Offset(cos(ang) * 230.0, sin(ang) * 230.0),
            Faction.neutral,
            hp: 65,
          );
        }

        // Вспомогательные фланговые звёзды
        addNode(const Offset(-260, -280), Faction.neutral);
        addNode(const Offset(-260, 280), Faction.neutral);
        addNode(const Offset(420, 0), Faction.neutral);
        break;

      // 11. ASTEROID CHASM (Гибрид: лабиринт из стен вокруг червоточины)
      case ConstellationType.labyrinthWormhole:
        addWormhole(Offset.zero, radius: 40.0, criticalMass: 30, poleAngle: pi / 2);

        addNode(const Offset(-480, 0), Faction.player, level: 1, startingUnits: 28);
        addNode(const Offset(480, 0), Faction.enemy1, level: 1, startingUnits: 28);

        addNode(const Offset(0, -320), Faction.neutral, hp: 80);
        addNode(const Offset(0, 320), Faction.neutral, hp: 80);
        addNode(const Offset(-240, -220), Faction.neutral);
        addNode(const Offset(-240, 220), Faction.neutral);
        addNode(const Offset(240, -220), Faction.neutral);
        addNode(const Offset(240, 220), Faction.neutral);

        // Лабиринтные стены, направляющие потоки к червоточине и флангам
        addWall(const Offset(-130, -380), const Offset(-130, -90), thickness: 18);
        addWall(const Offset(-130, 90), const Offset(-130, 380), thickness: 18);
        addWall(const Offset(130, -380), const Offset(130, -90), thickness: 18);
        addWall(const Offset(130, 90), const Offset(130, 380), thickness: 18);
        break;

      // 12. PULSAR OMEGA (Стартовые звёзды 3+ уровня с атомными орбитами)
      case ConstellationType.pulsarOmega:
        // Все стартовые базы сразу 3-го уровня с активными атомными орбитами!
        addNode(const Offset(-460, 0), Faction.player, level: 3, hp: 100, startingUnits: 48);
        addNode(const Offset(230, -400), Faction.enemy1, level: 3, hp: 100, startingUnits: 44);
        addNode(const Offset(230, 400), Faction.enemy2, level: 3, hp: 100, startingUnits: 44);

        // Центральная мега-звезда 3-го уровня
        addNode(Offset.zero, Faction.neutral, level: 3, hp: 100);

        // Орбитальные сателлиты 2-го уровня
        for (int i = 0; i < 6; i++) {
          double ang = (2 * pi / 6) * i;
          addNode(
            Offset(cos(ang) * 260.0, sin(ang) * 260.0),
            Faction.neutral,
            level: 0,
            hp: 75,
            orbitCenter: Offset.zero,
            orbitRadius: 260.0,
            orbitSpeed: 0.035,
            orbitAngle: ang,
          );
        }
        break;
    }

    return ConstellationSaveData(
      type: type,
      nodes: genNodes,
      rendezvousPoints: [],
      units: genUnits,
      obstacles: genWalls,
      wormholes: genWormholes,
      winner: null,
      cameraOffset: Offset.zero,
      cameraZoom: 0.65,
      isStarted: markStarted,
    );
  }

  void _spawnUnitsInstant(StarNode node, Faction faction, int count) {
    for (int i = 0; i < count; i++) {
      double ang = _rng.nextDouble() * pi * 2;
      double dist = node.radius + 14.0 + _rng.nextDouble() * 34.0;
      Offset pos = node.pos + Offset(cos(ang) * dist, sin(ang) * dist);
      _units.add(
        SwarmUnit(
          pos: pos,
          vel: Offset.zero,
          faction: faction,
          targetNode: node,
          isOrbiting: true,
          isUpgradingTarget: false,
          orbitAngle: ang,
          orbitDist: dist,
          speed: 95.0 + _rng.nextDouble() * 30.0,
          phase: _rng.nextDouble() * pi * 2,
        ),
      );
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTime == Duration.zero) {
      _lastTime = elapsed;
      return;
    }
    double dt = (elapsed - _lastTime).inMicroseconds / 1000000.0;
    _lastTime = elapsed;
    if (dt > 0.05) dt = 0.05;

    if (_inMenu) {
      _globalTime += dt;
    } else if (!_isPaused && _winner == null) {
      _updateGame(dt * _gameSpeed);
      _autoSaveTimer += dt;
      if (_autoSaveTimer >= 4.0) {
        _autoSaveTimer = 0.0;
        _saveCurrentLevelSnapshot();
        _persistStateToDisk();
      }
    }
    setState(() {});
  }

  // Физика столкновения частиц с препятствиями (стенами лабиринтов)
  Offset _resolveWallCollision(
      Offset pos, Offset vel, ObstacleWall wall, double unitRadius) {
    final ab = wall.end - wall.start;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 0.0001) return pos;

    final ap = pos - wall.start;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    final closest = wall.start + ab * t;
    final diff = pos - closest;
    final dist = diff.distance;
    final minDist = (wall.thickness / 2.0) + unitRadius;

    if (dist < minDist) {
      Offset normal;
      if (dist > 0.001) {
        normal = diff / dist;
      } else {
        final invLen = 1.0 / sqrt(lenSq);
        normal = Offset(-ab.dy * invLen, ab.dx * invLen);
      }
      return closest + normal * (minDist + 0.5);
    }
    return pos;
  }

  Offset _deflectVelocityByWall(
      Offset pos, Offset vel, ObstacleWall wall, double unitRadius) {
    final ab = wall.end - wall.start;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 0.0001) return vel;

    final ap = pos - wall.start;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    final closest = wall.start + ab * t;
    final diff = pos - closest;
    final dist = diff.distance;
    final minDist = (wall.thickness / 2.0) + unitRadius + 3.0;

    if (dist < minDist) {
      Offset normal;
      if (dist > 0.001) {
        normal = diff / dist;
      } else {
        final invLen = 1.0 / sqrt(lenSq);
        normal = Offset(-ab.dy * invLen, ab.dx * invLen);
      }
      final vDotN = vel.dx * normal.dx + vel.dy * normal.dy;
      if (vDotN < 0) {
        return vel - normal * (vDotN * 1.3);
      }
    }
    return vel;
  }

  void _updateGame(double dt) {
    _globalTime += dt;

    // 1. Обновление орбит и производства звёзд
    for (final node in _nodes) {
      if (node.orbitCenter != null && node.orbitRadius > 0) {
        node.orbitAngle += node.orbitSpeed * dt;
        node.pos = node.orbitCenter! +
            Offset(
              cos(node.orbitAngle) * node.orbitRadius,
              sin(node.orbitAngle) * node.orbitRadius,
            );
      }

      if (node.owner != Faction.neutral) {
        node.spawnAccumulator += node.productionRate * dt;
        while (node.spawnAccumulator >= 1.0) {
          node.spawnAccumulator -= 1.0;
          _spawnUnitsInstant(node, node.owner, 1);
        }
        if (node.hp < 100.0) {
          node.hp = min(100.0, node.hp + 2.5 * dt);
        }
      }
    }

    if (_isBoxSelecting &&
        _selectionBoxStartWorld != null &&
        _selectionBoxCurrentWorld != null) {
      final rect =
          Rect.fromPoints(_selectionBoxStartWorld!, _selectionBoxCurrentWorld!);
      _updateSelectionInRect(rect, triggerHaptic: false);
    }

    for (final rp in _rendezvousPoints) {
      rp.pulse += dt * 3.0;
    }

    // 2. Червоточины: вращение, пульсация и извержение полярных джетов
    for (final wh in _wormholes) {
      wh.spinPhase += dt * (wh.isErupting ? 5.5 : 1.5);
      wh.pulsePhase += dt * (wh.isErupting ? 6.5 : 2.0);

      if (wh.isErupting) {
        wh.eruptionTimer -= dt;
        wh.jetAccumulator += dt * 26.0;

        Faction jetFaction = wh.lastAbsorbedFaction;
        int maxContr = -1;
        for (final entry in wh.factionContributions.entries) {
          if (entry.value > maxContr) {
            maxContr = entry.value;
            jetFaction = entry.key;
          }
        }
        if (jetFaction == Faction.neutral) jetFaction = Faction.player;

        while (wh.jetAccumulator >= 1.0) {
          wh.jetAccumulator -= 1.0;

          // Спавн частиц из обоих полюсов (Северный и Южный джет)
          for (int p = 0; p < 2; p++) {
            final double poleBase = p == 0 ? wh.poleAngle : wh.poleAngle + pi;
            final double spread = (_rng.nextDouble() - 0.5) * 0.24;
            final double jetAng = poleBase + spread;
            final Offset spawnPos = wh.pos +
                Offset(cos(poleBase), sin(poleBase)) * (wh.radius + 12.0);
            final Offset jetVel =
                Offset(cos(jetAng), sin(jetAng)) * (240.0 + _rng.nextDouble() * 50.0);

            _units.add(
              SwarmUnit(
                pos: spawnPos,
                vel: jetVel,
                faction: jetFaction,
                targetNode: null,
                targetRendezvous: null,
                targetWormhole: null,
                isOrbiting: false,
                isUpgradingTarget: false,
                orbitAngle: jetAng,
                orbitDist: 40.0,
                speed: 160.0 + _rng.nextDouble() * 40.0,
                phase: _rng.nextDouble() * pi * 2,
              ),
            );
            _spawnSparks(spawnPos, factionColor(jetFaction), 2, speed: 110.0);
          }
        }

        if (wh.eruptionTimer <= 0) {
          wh.isErupting = false;
          wh.storedUnits = 0;
          wh.factionContributions.clear();
          _waves.add(
            PulseWave(
              pos: wh.pos,
              color: Colors.white,
              maxRadius: wh.radius + 70.0,
            ),
          );
        }
      }
    }

    // 3. Физика частиц
    for (final u in _units) {
      if (u.dead) continue;

      // Полёт к червоточине
      if (u.targetWormhole != null) {
        final wh = u.targetWormhole!;
        final toWh = wh.pos - u.pos;
        final dist = toWh.distance;

        if (dist > wh.radius * 0.75) {
          Offset dir = toWh / dist;
          Offset perp = Offset(-dir.dy, dir.dx);
          double swirl = sin(_globalTime * 3.5 + u.phase) * 0.25;
          Offset steer = (dir + perp * swirl);
          steer = steer / steer.distance;
          u.vel = Offset.lerp(
            u.vel,
            steer * (u.speed * 1.45),
            min(1.0, dt * 6.0),
          )!;
          u.pos += u.vel * dt;
        } else {
          // Частица поглощается червоточиной
          u.dead = true;
          wh.storedUnits++;
          wh.factionContributions[u.faction] =
              (wh.factionContributions[u.faction] ?? 0) + 1;
          wh.lastAbsorbedFaction = u.faction;
          _spawnSparks(u.pos, factionColor(u.faction), 5, speed: 70.0);
          _waves.add(
            PulseWave(
              pos: wh.pos,
              color: factionColor(u.faction),
              maxRadius: wh.radius + 20.0,
            ),
          );
          _audio.playCapture();

          // Достижение критической массы
          if (wh.storedUnits >= wh.criticalMass && !wh.isErupting) {
            wh.isErupting = true;
            wh.eruptionTimer = wh.eruptionDuration;
            _waves.add(
              PulseWave(
                pos: wh.pos,
                color: const Color(0xFFE040FB),
                maxRadius: wh.radius + 150.0,
              ),
            );
            _spawnSparks(wh.pos, const Color(0xFF00E5FF), 40, speed: 200.0);
            _floatingTexts.add(
              FloatingText(
                pos: wh.pos + const Offset(0, -50),
                text: 'КРИТИЧЕСКАЯ МАССА! ДЖЕТ!',
                color: const Color(0xFFE040FB),
              ),
            );
          }
        }
        continue;
      }

      // Полёт к точке сбора (Рандеву)
      if (u.targetRendezvous != null) {
        final rv = u.targetRendezvous!;
        final toRv = rv.pos - u.pos;
        final dist = toRv.distance;

        if (u.isOrbiting) {
          u.orbitAngle += 0.55 * dt;
          double dynamicDist =
              u.orbitDist + sin(_globalTime * 2.0 + u.phase) * 3.5;
          Offset desiredPos = rv.pos +
              Offset(
                cos(u.orbitAngle) * dynamicDist,
                sin(u.orbitAngle) * dynamicDist,
              );
          u.vel = (desiredPos - u.pos) * 6.0;
          u.pos += u.vel * dt;
        } else {
          if (dist > 26.0) {
            Offset dir = toRv / dist;
            Offset perp = Offset(-dir.dy, dir.dx);
            double sway = sin(_globalTime * 4.0 + u.phase) * 0.2;
            Offset steer = (dir + perp * sway);
            steer = steer / steer.distance;
            u.vel = Offset.lerp(
              u.vel,
              steer * (u.speed * 1.3),
              min(1.0, dt * 5.0),
            )!;
            u.pos += u.vel * dt;
          } else {
            u.isOrbiting = true;
            u.orbitAngle = atan2(u.pos.dy - rv.pos.dy, u.pos.dx - rv.pos.dx);
            u.orbitDist = 10.0 + _rng.nextDouble() * 26.0;
          }
        }
        continue;
      }

      // Полёт к целевой звезде
      final target = u.targetNode;
      if (target == null) {
        // Свободный полёт в космосе (например, после извержения джета)
        u.pos += u.vel * dt;
        u.vel *= pow(0.85, dt).toDouble();
        continue;
      }

      final toTarget = target.pos - u.pos;
      final dist = toTarget.distance;

      if (u.isUpgradingTarget) {
        if (target.owner != u.faction) {
          u.isUpgradingTarget = false;
        } else if (target.level >= target.maxLevel) {
          u.isUpgradingTarget = false;
          if (dist <= target.radius + 45.0) {
            u.isOrbiting = true;
            u.orbitAngle =
                atan2(u.pos.dy - target.pos.dy, u.pos.dx - target.pos.dx);
            u.orbitDist = target.radius + 14.0 + _rng.nextDouble() * 30.0;
          }
        }
      }

      if (u.isOrbiting) {
        if (target.owner != u.faction) {
          u.isOrbiting = false;
        } else {
          double minOrbit = target.radius + 12.0;
          if (u.orbitDist < minOrbit) {
            u.orbitDist = minOrbit + _rng.nextDouble() * 28.0;
          }
          u.orbitAngle += (0.55 + (35.0 / max(25.0, u.orbitDist))) * dt;
          double dynamicDist =
              u.orbitDist + sin(_globalTime * 2.0 + u.phase) * 4.0;
          Offset desiredPos = target.pos +
              Offset(
                cos(u.orbitAngle) * dynamicDist,
                sin(u.orbitAngle) * dynamicDist,
              );
          u.vel = (desiredPos - u.pos) * 6.0;
          u.pos += u.vel * dt;
        }
      } else {
        if (u.isUpgradingTarget) {
          Offset dir = dist > 0.001 ? toTarget / dist : const Offset(1, 0);
          u.vel = Offset.lerp(
            u.vel,
            dir * (u.speed * 1.65),
            min(1.0, dt * 8.0),
          )!;
          u.pos += u.vel * dt;

          if (dist <= target.radius + 4.0) {
            u.dead = true;
            _onUnitHitNode(u, target);
          }
        } else if (dist > target.radius + 26.0) {
          Offset dir = toTarget / dist;
          Offset perp = Offset(-dir.dy, dir.dx);
          double sway = sin(_globalTime * 4.0 + u.phase) * 0.22;
          Offset steer = (dir + perp * sway);
          steer = steer / steer.distance;

          u.vel = Offset.lerp(
            u.vel,
            steer * (u.speed * 1.3),
            min(1.0, dt * 5.0),
          )!;
          u.pos += u.vel * dt;
        } else {
          if (target.owner == u.faction && target.hp >= 99.5) {
            u.isOrbiting = true;
            u.orbitAngle =
                atan2(u.pos.dy - target.pos.dy, u.pos.dx - target.pos.dx);
            u.orbitDist = target.radius + 12.0 + _rng.nextDouble() * 32.0;
          } else {
            Offset dir = dist > 0.001 ? toTarget / dist : const Offset(1, 0);
            u.pos += dir * (u.speed * 1.4) * dt;

            if (dist <= target.radius + 5.0) {
              u.dead = true;
              _onUnitHitNode(u, target);
            }
          }
        }
      }
    }

    // 4. Столкновения с препятствиями (стенами лабиринтов)
    if (_obstacles.isNotEmpty) {
      for (final u in _units) {
        if (u.dead) continue;
        for (final wall in _obstacles) {
          u.pos = _resolveWallCollision(u.pos, u.vel, wall, 4.0);
          u.vel = _deflectVelocityByWall(u.pos, u.vel, wall, 4.0);
        }
      }
    }

    _handleUnitCollisions();
    _units.removeWhere((u) => u.dead);
    _selectedUnits.removeWhere((u) => u.dead);

    _rendezvousPoints.removeWhere(
      (rv) => !_units.any((u) => !u.dead && u.targetRendezvous == rv),
    );
    _selectedRendezvous.removeWhere((rv) => !_rendezvousPoints.contains(rv));

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel *= pow(0.18, dt).toDouble();
      s.life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);

    for (final w in _waves) {
      w.life -= dt * 1.4;
      w.radius = ui.lerpDouble(w.maxRadius, 12.0, max(0.0, w.life))!;
    }
    _waves.removeWhere((w) => w.life <= 0);

    for (final ft in _floatingTexts) {
      ft.pos += Offset(0, -28.0 * dt);
      ft.life -= dt * 1.1;
    }
    _floatingTexts.removeWhere((ft) => ft.life <= 0);

    _aiTimer += dt;
    if (_aiTimer >= 0.85) {
      _aiTimer = 0.0;
      _runAI(Faction.enemy1);
      _runAI(Faction.enemy2);
      _checkVictoryCondition();
    }
  }

  void _onUnitHitNode(SwarmUnit unit, StarNode node) {
    final color = factionColor(unit.faction);
    _spawnSparks(unit.pos, color, 5, speed: 65.0);

    if (node.owner == unit.faction) {
      if (node.hp < 99.5) {
        node.hp = min(100.0, node.hp + 2.5);
        return;
      }

      if (unit.isUpgradingTarget && node.level < node.maxLevel) {
        node.investedUnits++;

        if (node.investedUnits >= node.upgradeCost) {
          node.investedUnits = 0;
          node.level++;

          for (final other in _units) {
            if (!other.dead &&
                other.targetNode == node &&
                other.faction == node.owner) {
              other.isUpgradingTarget = false;
              if (other.isOrbiting && other.orbitDist < node.radius + 14.0) {
                other.orbitDist =
                    node.radius + 14.0 + _rng.nextDouble() * 30.0;
              }
            }
          }

          _waves.add(
            PulseWave(
              pos: node.pos,
              color: Colors.amberAccent,
              maxRadius: node.radius + 85,
            ),
          );
          _spawnSparks(node.pos, color, 36, speed: 165);
          if (node.owner == Faction.player) {
            _audio.playUpgrade();
            _floatingTexts.add(
              FloatingText(
                pos: node.pos + Offset(0, -node.radius - 20),
                text: 'УРОВЕНЬ ${node.level}!',
                color: Colors.cyanAccent,
              ),
            );
          }
        }
      }
      return;
    }

    node.hp -= 2.6;
    if (node.hp <= 0) {
      if (node.owner != Faction.neutral) {
        node.owner = Faction.neutral;
        node.level = 0;
        node.investedUnits = 0;
        node.hp = 25.0;
        _selectedNodes.remove(node);
        _waves.add(
          PulseWave(pos: node.pos, color: Colors.white, maxRadius: 115),
        );
        _spawnSparks(node.pos, Colors.white, 26, speed: 155.0);
      } else {
        node.owner = unit.faction;
        node.level = 1;
        node.investedUnits = 0;
        node.hp = 100.0;
        _waves.add(PulseWave(pos: node.pos, color: color, maxRadius: 135));
        _spawnSparks(node.pos, color, 34, speed: 175.0);
        if (unit.faction == Faction.player) {
          _audio.playCapture();
        }
      }
    }
  }

  void _handleUnitCollisions() {
    const double cellSize = 36.0;
    final Map<int, List<SwarmUnit>> grid = {};

    int cellHash(double x, double y) {
      int cx = (x / cellSize).floor();
      int cy = (y / cellSize).floor();
      return (cx * 73856093) ^ (cy * 19349663);
    }

    for (final u in _units) {
      if (u.dead) continue;
      final h = cellHash(u.pos.dx, u.pos.dy);
      (grid[h] ??= []).add(u);
    }

    for (final cellUnits in grid.values) {
      if (cellUnits.length < 2) continue;
      for (int i = 0; i < cellUnits.length; i++) {
        final a = cellUnits[i];
        if (a.dead) continue;
        for (int j = i + 1; j < cellUnits.length; j++) {
          final b = cellUnits[j];
          if (b.dead || a.faction == b.faction) continue;

          final dx = a.pos.dx - b.pos.dx;
          final dy = a.pos.dy - b.pos.dy;
          if (dx * dx + dy * dy < 144.0) {
            a.dead = true;
            b.dead = true;
            final mid = Offset(
              (a.pos.dx + b.pos.dx) * 0.5,
              (a.pos.dy + b.pos.dy) * 0.5,
            );
            _spawnSparks(mid, factionColor(a.faction), 5, speed: 100.0);
            _spawnSparks(mid, factionColor(b.faction), 5, speed: 100.0);
            break;
          }
        }
      }
    }
  }

  void _spawnSparks(Offset pos, Color color, int count, {double speed = 90.0}) {
    for (int i = 0; i < count; i++) {
      double ang = _rng.nextDouble() * pi * 2;
      double spd = (0.25 + _rng.nextDouble() * 0.75) * speed;
      _sparks.add(
        SparkParticle(
          pos: pos,
          vel: Offset(cos(ang) * spd, sin(ang) * spd),
          color: color,
          life: 0.28 + _rng.nextDouble() * 0.4,
          size: 1.6 + _rng.nextDouble() * 2.4,
        ),
      );
    }
  }

  List<SwarmUnit> _getOrbitingNodeUnits(StarNode node, Faction faction) {
    return _units
        .where((u) =>
            !u.dead &&
            u.faction == faction &&
            u.targetNode == node &&
            (u.isOrbiting ||
                (u.pos - node.pos).distance <= node.radius + 65.0) &&
            !u.isUpgradingTarget)
        .toList();
  }

  void _runAI(Faction aiFaction) {
    final myNodes = _nodes.where((n) => n.owner == aiFaction).toList();
    if (myNodes.isEmpty) return;

    // Шанс отправить частицы в червоточину для вызова извержения
    if (_wormholes.isNotEmpty && _rng.nextDouble() < 0.28) {
      for (final wh in _wormholes) {
        if (!wh.isErupting && wh.storedUnits < wh.criticalMass) {
          for (final srcNode in myNodes) {
            final available = _getOrbitingNodeUnits(srcNode, aiFaction);
            if (available.length > 22) {
              int sendCount = min(
                  available.length - 10, wh.criticalMass - wh.storedUnits);
              for (int i = 0; i < sendCount; i++) {
                final u = available[i];
                u.targetNode = null;
                u.targetRendezvous = null;
                u.targetWormhole = wh;
                u.isOrbiting = false;
                u.isUpgradingTarget = false;
              }
              break;
            }
          }
        }
      }
    }

    for (final node in myNodes) {
      final nodeUnits = _getOrbitingNodeUnits(node, aiFaction);
      final alreadyInbound = _units
          .where((u) =>
              !u.dead &&
              u.faction == aiFaction &&
              u.targetNode == node &&
              u.isUpgradingTarget)
          .length;
      final needed = node.upgradeCost - node.investedUnits - alreadyInbound;

      if (node.level < node.maxLevel &&
          needed > 0 &&
          nodeUnits.length >= needed + 10 &&
          _rng.nextDouble() < 0.45) {
        _upgradeNode(node, nodeUnits);
        continue;
      }

      if (nodeUnits.length > 24) {
        StarNode? bestTarget;
        double bestScore = double.infinity;

        for (final candidate in _nodes) {
          if (candidate == node) continue;
          if (candidate.owner == aiFaction && candidate.hp > 80) continue;

          double dist = (candidate.pos - node.pos).distance;
          int enemyDefenders = _units
              .where((u) =>
                  !u.dead &&
                  u.targetNode == candidate &&
                  u.faction != aiFaction)
              .length;

          double score = dist * 0.9 + enemyDefenders * 7.5 + candidate.hp * 1.4;
          if (candidate.owner == Faction.neutral) score *= 0.68;
          if (candidate.owner == aiFaction && candidate.hp <= 80) score *= 0.4;

          if (score < bestScore) {
            bestScore = score;
            bestTarget = candidate;
          }
        }

        if (bestTarget != null) {
          _sendUnitsFromNodes([node], bestTarget, aiFaction, ratio: 0.75);
        }
      }
    }
  }

  void _checkVictoryCondition() {
    bool playerAlive = _nodes.any((n) => n.owner == Faction.player) ||
        _units.any((u) => u.faction == Faction.player);
    bool enemiesAlive = _nodes.any(
          (n) => n.owner == Faction.enemy1 || n.owner == Faction.enemy2,
        ) ||
        _units.any(
          (u) => u.faction == Faction.enemy1 || u.faction == Faction.enemy2,
        );

    if (!playerAlive) {
      _winner = Faction.enemy1;
      _saveCurrentLevelSnapshot();
      _persistStateToDisk();
    } else if (!enemiesAlive) {
      _winner = Faction.player;
      _saveCurrentLevelSnapshot();
      _persistStateToDisk();
    }
  }

  void _sendUnitsFromNodes(
    Iterable<StarNode> sources,
    StarNode target,
    Faction faction, {
    double ratio = 1.0,
  }) {
    int launched = 0;
    for (final src in sources) {
      if (src == target) continue;
      final available = _getOrbitingNodeUnits(src, faction);
      if (available.isEmpty) continue;

      int countToSend =
          ratio >= 0.99 ? available.length : (available.length * ratio).ceil();
      for (int i = 0; i < countToSend && i < available.length; i++) {
        available[i].targetNode = target;
        available[i].targetRendezvous = null;
        available[i].targetWormhole = null;
        available[i].isOrbiting = false;
        available[i].isUpgradingTarget = false;
        launched++;
      }
    }

    if (launched > 0) {
      _waves.add(
        PulseWave(
          pos: target.pos,
          color: factionColor(faction),
          maxRadius: target.radius + 42,
        ),
      );
      if (faction == Faction.player) {
        _audio.playLaunch();
      }
    }
  }

  bool _isUnitPartOfCurrentSelection(SwarmUnit u) {
    if (u.dead || u.faction != Faction.player) return false;
    if (_selectedUnits.contains(u)) return true;
    if (u.targetRendezvous != null &&
        _selectedRendezvous.contains(u.targetRendezvous)) {
      return true;
    }
    if (u.targetNode != null &&
        _selectedNodes.contains(u.targetNode) &&
        (u.isOrbiting ||
            (u.pos - u.targetNode!.pos).distance <=
                u.targetNode!.radius + 65.0)) {
      return true;
    }
    return false;
  }

  int _dispatchSelectedToNode(StarNode target) {
    int launched = 0;

    for (final u in _units) {
      if (!_isUnitPartOfCurrentSelection(u)) continue;

      if (u.targetNode == target &&
          u.targetRendezvous == null &&
          u.targetWormhole == null &&
          u.isOrbiting &&
          !u.isUpgradingTarget) {
        continue;
      }

      u.targetNode = target;
      u.targetRendezvous = null;
      u.targetWormhole = null;
      u.isOrbiting = false;
      u.isUpgradingTarget = false;
      launched++;
    }

    if (launched > 0) {
      _waves.add(
        PulseWave(
          pos: target.pos,
          color: factionColor(Faction.player),
          maxRadius: target.radius + 42,
        ),
      );
      _audio.playLaunch();
    }
    return launched;
  }

  int _dispatchSelectedToSpace(Offset worldPos) {
    final newRv = RendezvousPoint(_rvIdCounter++, worldPos, Faction.player);
    int launched = 0;

    for (final u in _units) {
      if (!_isUnitPartOfCurrentSelection(u)) continue;

      u.targetNode = null;
      u.targetRendezvous = newRv;
      u.targetWormhole = null;
      u.isOrbiting = false;
      u.isUpgradingTarget = false;
      launched++;
    }

    if (launched > 0) {
      _rendezvousPoints.add(newRv);
      _waves.add(
        PulseWave(
          pos: newRv.pos,
          color: factionColor(Faction.player),
          maxRadius: 48,
        ),
      );
      _audio.playLaunch();
    }
    return launched;
  }

  int _dispatchSelectedToWormhole(Wormhole target) {
    int launched = 0;

    for (final u in _units) {
      if (!_isUnitPartOfCurrentSelection(u)) continue;

      u.targetNode = null;
      u.targetRendezvous = null;
      u.targetWormhole = target;
      u.isOrbiting = false;
      u.isUpgradingTarget = false;
      launched++;
    }

    if (launched > 0) {
      _waves.add(
        PulseWave(
          pos: target.pos,
          color: const Color(0xFFE040FB),
          maxRadius: target.radius + 42,
        ),
      );
      _audio.playLaunch();
    }
    return launched;
  }

  bool _upgradeNode(StarNode node, List<SwarmUnit> availableUnits) {
    if (node.level >= node.maxLevel) {
      if (node.owner == Faction.player) {
        _floatingTexts.add(
          FloatingText(
            pos: node.pos + Offset(0, -node.radius - 18),
            text: 'МАКС. УР. 4',
            color: Colors.amberAccent,
          ),
        );
      }
      return false;
    }

    if (availableUnits.isEmpty) return false;

    final alreadyInbound = _units
        .where((u) =>
            !u.dead &&
            u.faction == node.owner &&
            u.targetNode == node &&
            u.isUpgradingTarget)
        .length;

    int needed = node.upgradeCost - node.investedUnits - alreadyInbound;
    if (needed <= 0) return false;

    availableUnits.sort(
      (a, b) => (a.pos - node.pos)
          .distanceSquared
          .compareTo((b.pos - node.pos).distanceSquared),
    );

    int toSend = min(availableUnits.length, needed);

    for (int i = 0; i < toSend; i++) {
      final u = availableUnits[i];
      u.targetNode = node;
      u.targetRendezvous = null;
      u.targetWormhole = null;
      u.isOrbiting = false;
      u.isUpgradingTarget = true;
    }

    _waves.add(
      PulseWave(
        pos: node.pos,
        color: Colors.amberAccent,
        maxRadius: node.radius + 36,
      ),
    );

    if (node.owner == Faction.player) {
      _audio.playLaunch();
    }
    return true;
  }

  Offset _screenToWorld(Offset screenPos, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    return (screenPos - center - _cameraOffset) / _cameraZoom;
  }

  StarNode? _findNodeAtWorld(Offset worldPos, {double extraHitRadius = 26.0}) {
    StarNode? closest;
    double bestDist = double.infinity;
    for (final node in _nodes) {
      double d = (node.pos - worldPos).distance;
      if (d <= node.radius + extraHitRadius && d < bestDist) {
        bestDist = d;
        closest = node;
      }
    }
    return closest;
  }

  RendezvousPoint? _findRendezvousAtWorld(Offset worldPos) {
    RendezvousPoint? closest;
    double bestDist = double.infinity;
    for (final rp in _rendezvousPoints) {
      double d = (rp.pos - worldPos).distance;
      if (d <= 42.0 && d < bestDist) {
        bestDist = d;
        closest = rp;
      }
    }
    return closest;
  }

  Wormhole? _findWormholeAtWorld(Offset worldPos) {
    Wormhole? closest;
    double bestDist = double.infinity;
    for (final wh in _wormholes) {
      double d = (wh.pos - worldPos).distance;
      if (d <= wh.radius + 24.0 && d < bestDist) {
        bestDist = d;
        closest = wh;
      }
    }
    return closest;
  }

  void _updateSelectionInRect(Rect worldRect, {bool triggerHaptic = true}) {
    int prevCount = _selectedNodes.length +
        _selectedRendezvous.length +
        _selectedUnits.length;

    _selectedNodes.clear();
    _selectedRendezvous.clear();
    _selectedUnits.clear();

    for (final node in _nodes) {
      if (node.owner == Faction.player && worldRect.contains(node.pos)) {
        _selectedNodes.add(node);
      }
    }

    for (final rp in _rendezvousPoints) {
      if (rp.faction == Faction.player && worldRect.contains(rp.pos)) {
        _selectedRendezvous.add(rp);
      }
    }

    for (final u in _units) {
      if (!u.dead &&
          u.faction == Faction.player &&
          worldRect.contains(u.pos)) {
        _selectedUnits.add(u);
      }
    }

    int newCount = _selectedNodes.length +
        _selectedRendezvous.length +
        _selectedUnits.length;
    if (triggerHaptic && newCount != prevCount && newCount > 0) {
      HapticFeedback.selectionClick();
    }
  }

  void _onPointerDown(PointerDownEvent event, Size viewportSize) {
    _activePointers[event.pointer] = event.localPosition;

    if (_activePointers.length >= 2) {
      _gestureWasMultitouch = true;
      final pts = _activePointers.values.toList();
      _lastPinchFocal = (pts[0] + pts[1]) * 0.5;
      _lastPinchDist = (pts[0] - pts[1]).distance;
      _isBoxSelecting = false;
      _selectionBoxStartWorld = null;
      _selectionBoxCurrentWorld = null;
      return;
    }

    if (_activePointers.length == 1) {
      _gestureWasMultitouch = false;
      _primaryPointerId = event.pointer;
      _pointerDownScreenPos = event.localPosition;
      _isBoxSelecting = false;

      final worldPos = _screenToWorld(event.localPosition, viewportSize);
      _selectionBoxStartWorld = worldPos;
      _selectionBoxCurrentWorld = worldPos;
    }
  }

  void _onPointerMove(PointerMoveEvent event, Size viewportSize) {
    _activePointers[event.pointer] = event.localPosition;

    if (_activePointers.length >= 2) {
      _gestureWasMultitouch = true;
      final pts = _activePointers.values.toList();
      final focal = (pts[0] + pts[1]) * 0.5;
      final dist = (pts[0] - pts[1]).distance;

      if (_lastPinchFocal != null &&
          _lastPinchDist != null &&
          _lastPinchDist! > 10) {
        final scaleChange = dist / _lastPinchDist!;
        _cameraZoom = (_cameraZoom * scaleChange).clamp(0.32, 1.65);
        _cameraOffset += (focal - _lastPinchFocal!);
      }
      _lastPinchFocal = focal;
      _lastPinchDist = dist;
      return;
    }

    if (_pointerDownScreenPos != null &&
        (event.localPosition - _pointerDownScreenPos!).distance > 18.0) {
      _isBoxSelecting = true;
    }

    if (_isBoxSelecting && _selectionBoxStartWorld != null) {
      final worldPos = _screenToWorld(event.localPosition, viewportSize);
      _selectionBoxCurrentWorld = worldPos;
      final rect =
          Rect.fromPoints(_selectionBoxStartWorld!, _selectionBoxCurrentWorld!);
      _updateSelectionInRect(rect, triggerHaptic: true);
    }
  }

  void _onPointerUp(PointerUpEvent event, Size viewportSize) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      _lastPinchFocal = null;
      _lastPinchDist = null;
    }

    if (_gestureWasMultitouch) {
      if (_activePointers.isEmpty) {
        _gestureWasMultitouch = false;
        _primaryPointerId = null;
      }
      return;
    }

    if (event.pointer == _primaryPointerId) {
      final worldPos = _screenToWorld(event.localPosition, viewportSize);

      if (_isBoxSelecting &&
          _selectionBoxStartWorld != null &&
          _selectionBoxCurrentWorld != null) {
        final rect = Rect.fromPoints(
            _selectionBoxStartWorld!, _selectionBoxCurrentWorld!);
        _updateSelectionInRect(rect, triggerHaptic: false);
        _isBoxSelecting = false;
        _selectionBoxStartWorld = null;
        _selectionBoxCurrentWorld = null;
      } else {
        _handleSingleOrDoubleTap(worldPos);
        _selectionBoxStartWorld = null;
        _selectionBoxCurrentWorld = null;
      }

      _primaryPointerId = null;
    }
  }

  void _handleSingleOrDoubleTap(Offset worldPos) {
    final hitNode = _findNodeAtWorld(worldPos);
    final hitRv = _findRendezvousAtWorld(worldPos);
    final hitWormhole = _findWormholeAtWorld(worldPos);
    final now = DateTime.now();

    if (hitWormhole != null) {
      if (_hasAnySelection) {
        _dispatchSelectedToWormhole(hitWormhole);
        HapticFeedback.mediumImpact();
        _clearSelection();
      } else {
        _floatingTexts.add(
          FloatingText(
            pos: hitWormhole.pos + Offset(0, -hitWormhole.radius - 18),
            text: 'ЧЕРВОТОЧИНА [${hitWormhole.storedUnits}/${hitWormhole.criticalMass}]',
            color: const Color(0xFFE040FB),
          ),
        );
        _waves.add(
          PulseWave(
            pos: hitWormhole.pos,
            color: const Color(0xFFE040FB),
            maxRadius: hitWormhole.radius + 32,
          ),
        );
        HapticFeedback.selectionClick();
      }
      _lastTappedNode = null;
      return;
    }

    if (hitNode != null) {
      final bool isDoubleTapOnOwnNode = hitNode.owner == Faction.player &&
          _lastTappedNode == hitNode &&
          now.difference(_lastTapTime).inMilliseconds < 450;

      final bool hasOtherSelectionToSend = _selectedRendezvous.isNotEmpty ||
          _selectedNodes.any((n) => n != hitNode) ||
          _selectedUnits.any((u) => !u.dead && u.targetNode != hitNode);

      if (isDoubleTapOnOwnNode) {
        final orbitUnits = _getOrbitingNodeUnits(hitNode, Faction.player);
        _upgradeNode(hitNode, orbitUnits);
        HapticFeedback.heavyImpact();
        _lastTappedNode = null;
        _clearSelection();
      } else if (hasOtherSelectionToSend) {
        _dispatchSelectedToNode(hitNode);
        HapticFeedback.lightImpact();
        _clearSelection();

        if (hitNode.owner == Faction.player) {
          _lastTappedNode = hitNode;
          _lastTapTime = now;
        } else {
          _lastTappedNode = null;
        }
      } else if (hitNode.owner == Faction.player) {
        _clearSelection();
        _selectedNodes.add(hitNode);
        HapticFeedback.selectionClick();
        _lastTappedNode = hitNode;
        _lastTapTime = now;
      } else {
        final nearbyUnits = _units
            .where((u) =>
                !u.dead &&
                u.faction == Faction.player &&
                (u.pos - worldPos).distance <= 48.0)
            .toList();
        _clearSelection();
        if (nearbyUnits.isNotEmpty) {
          _selectedUnits.addAll(nearbyUnits);
          HapticFeedback.selectionClick();
        }
        _lastTappedNode = null;
      }
    } else if (hitRv != null && !_hasAnySelection) {
      _clearSelection();
      _selectedRendezvous.add(hitRv);
      HapticFeedback.selectionClick();
      _lastTappedNode = null;
    } else {
      if (_hasAnySelection) {
        _dispatchSelectedToSpace(worldPos);
        HapticFeedback.mediumImpact();
        _clearSelection();
      } else {
        final nearbyUnits = _units
            .where((u) =>
                !u.dead &&
                u.faction == Faction.player &&
                (u.pos - worldPos).distance <= 52.0)
            .toList();
        if (nearbyUnits.isNotEmpty) {
          _clearSelection();
          _selectedUnits.addAll(nearbyUnits);
          HapticFeedback.selectionClick();
        } else {
          _clearSelection();
        }
      }
      _lastTappedNode = null;
    }
  }

  int _countFactionUnits(Faction f) =>
      _units.where((u) => !u.dead && u.faction == f).length;

  int _countFactionNodes(Faction f) =>
      _nodes.where((n) => n.owner == f).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize =
              Size(constraints.maxWidth, constraints.maxHeight);

          if (_inMenu) {
            if (_selectedGalaxy == null) {
              return _buildGalaxyMenu(viewportSize);
            }
            return _buildConstellationMenu(viewportSize);
          }
          return _buildActiveGameStack(viewportSize);
        },
      ),
    );
  }

  // 1. СТАРТОВАЯ СТРАНИЦА: ВЫБОР ГАЛАКТИКИ
  Widget _buildGalaxyMenu(Size viewportSize) {
    return Stack(
      children: [
        CustomPaint(
          size: viewportSize,
          painter: MenuBackgroundPainter(
            globalTime: _globalTime,
            bgStars: _bgStars,
            pageOffset: _galaxyPageValue,
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AURALUX: GALAXY ATLAS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            letterSpacing: 4.5,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'ВЫБЕРИТЕ ГАЛАКТИКУ ДЛЯ ИССЛЕДОВАНИЯ СОЗВЕЗДИЙ',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    _buildTopButton(
                      icon:
                          _audio.isMuted ? Icons.volume_off : Icons.volume_up,
                      onTap: () async {
                        await _audio.toggleMute();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _galaxyPageController,
                  itemCount: galaxies.length,
                  onPageChanged: (idx) {
                    HapticFeedback.selectionClick();
                    setState(() => _galaxyPageIndex = idx);
                  },
                  itemBuilder: (context, index) {
                    final galaxy = galaxies[index];
                    final double delta = (_galaxyPageValue - index).abs();
                    final double scale = (1.0 - delta * 0.12).clamp(0.85, 1.0);
                    final double opacity =
                        (1.0 - delta * 0.45).clamp(0.45, 1.0);

                    return Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: _buildGalaxyCard(galaxy),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    galaxies.length,
                    (i) {
                      final active = i == _galaxyPageIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: active ? 24 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? galaxies[i].primaryColor
                              : Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGalaxyCard(GalaxyDefinition galaxy) {
    int capturedCount = 0;
    for (final cType in galaxy.constellations) {
      if (_savedConstellations[cType]?.winner == Faction.player) {
        capturedCount++;
      }
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        setState(() {
          _selectedGalaxy = galaxy.type;
          _constellationPageIndex = 0;
          _constellationPageValue = 0.0;
          if (_constellationPageController.hasClients) {
            _constellationPageController.jumpToPage(0);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF070D20).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: galaxy.primaryColor.withValues(alpha: 0.45),
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: galaxy.primaryColor.withValues(alpha: 0.12),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Анимированная галактическая спираль на фоне карточки
              Positioned.fill(
                child: CustomPaint(
                  painter: GalaxySpiralPainter(
                    primaryColor: galaxy.primaryColor,
                    globalTime: _globalTime,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: galaxy.primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: galaxy.primaryColor.withValues(alpha: 0.5),
                              width: 1.0,
                            ),
                          ),
                          child: Icon(
                            galaxy.icon,
                            color: galaxy.primaryColor,
                            size: 26,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white24, width: 0.9),
                          ),
                          child: Text(
                            '$capturedCount / ${galaxy.constellations.length} ЗАХВАЧЕНО',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10.5,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          galaxy.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            letterSpacing: 3.5,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: galaxy.primaryColor.withValues(alpha: 0.6),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          galaxy.subtitle,
                          style: TextStyle(
                            color: galaxy.primaryColor,
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          galaxy.description,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${galaxy.constellations.length} СОЗВЕЗДИЯ',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: galaxy.primaryColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: galaxy.primaryColor,
                              width: 1.2,
                            ),
                          ),
                          child: const Row(
                            children: [
                              Text(
                                'ВОЙТИ В ГАЛАКТИКУ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward_ios,
                                  size: 11, color: Colors.white),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 2. ВНУТРЕННИЙ ЭКРАН: ВЫБОР СОЗВЕЗДИЯ В ТЕКУЩЕЙ ГАЛАКТИКЕ
  Widget _buildConstellationMenu(Size viewportSize) {
    final currentGalaxy = galaxies.firstWhere(
      (g) => g.type == _selectedGalaxy,
      orElse: () => galaxies[0],
    );
    final constellationList = currentGalaxy.constellations;

    return Stack(
      children: [
        CustomPaint(
          size: viewportSize,
          painter: MenuBackgroundPainter(
            globalTime: _globalTime,
            bgStars: _bgStars,
            pageOffset: _constellationPageValue,
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _selectedGalaxy = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white24, width: 1.0),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.arrow_back_ios,
                                    size: 13, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'ГАЛАКТИКИ',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentGalaxy.title,
                              style: TextStyle(
                                color: currentGalaxy.primaryColor,
                                fontSize: 16,
                                letterSpacing: 3.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'ВЫБЕРИТЕ СОЗВЕЗДИЕ ДЛЯ СРАЖЕНИЯ',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 9.5,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    _buildTopButton(
                      icon:
                          _audio.isMuted ? Icons.volume_off : Icons.volume_up,
                      onTap: () async {
                        await _audio.toggleMute();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _constellationPageController,
                  itemCount: constellationList.length,
                  onPageChanged: (idx) {
                    HapticFeedback.selectionClick();
                    setState(() => _constellationPageIndex = idx);
                  },
                  itemBuilder: (context, index) {
                    final type = constellationList[index];
                    final saveData = _savedConstellations[type] ??
                        _buildInitialConstellationData(type);

                    final double delta =
                        (_constellationPageValue - index).abs();
                    final double scale =
                        (1.0 - delta * 0.14).clamp(0.84, 1.0);
                    final double opacity =
                        (1.0 - delta * 0.45).clamp(0.45, 1.0);

                    return Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: _buildConstellationCard(type, saveData),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    constellationList.length,
                    (i) {
                      final active = i == _constellationPageIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: active ? 24 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? currentGalaxy.primaryColor
                              : Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConstellationCard(
      ConstellationType type, ConstellationSaveData saveData) {
    final bool hasSavedGame = saveData.isStarted;
    final Faction? winner = saveData.winner;

    String statusLabel = 'НОВОЕ СОЗВЕЗДИЕ';
    Color statusColor = Colors.white60;
    if (winner == Faction.player) {
      statusLabel = 'СОЗВЕЗДИЕ ЗАХВАЧЕНО';
      statusColor = const Color(0xFF00E5FF);
    } else if (winner != null) {
      statusLabel = 'СОЗВЕЗДИЕ ПОТЕРЯНО';
      statusColor = const Color(0xFFFF1744);
    } else if (hasSavedGame) {
      statusLabel = 'В ПРОЦЕССЕ (СОХРАНЕНО)';
      statusColor = Colors.amberAccent;
    }

    final int pNodes = saveData.countNodes(Faction.player);
    final int e1Nodes = saveData.countNodes(Faction.enemy1);
    final int e2Nodes = saveData.countNodes(Faction.enemy2);
    final int nNodes = saveData.countNodes(Faction.neutral);

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _openConstellationFromMenu(type, forceRestart: false);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF070D20).withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.45),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: ConstellationPreviewPainter(
                    saveData: saveData,
                    globalTime: _globalTime,
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 18,
                right: 18,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          constellationTitle(type),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            letterSpacing: 3.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          constellationSubtitle(type),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.6),
                            width: 0.9),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 12,
                left: 18,
                right: 18,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildStarBadge(factionColor(Faction.player), pNodes),
                        const SizedBox(width: 8),
                        _buildStarBadge(factionColor(Faction.enemy1), e1Nodes),
                        const SizedBox(width: 8),
                        _buildStarBadge(factionColor(Faction.enemy2), e2Nodes),
                        const SizedBox(width: 8),
                        _buildStarBadge(factionColor(Faction.neutral), nNodes),
                      ],
                    ),
                    Row(
                      children: [
                        if (hasSavedGame)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.heavyImpact();
                                _openConstellationFromMenu(type,
                                    forceRestart: true);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.white30, width: 0.9),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.refresh,
                                        size: 14, color: Colors.white70),
                                    SizedBox(width: 5),
                                    Text(
                                      'НАЧАТЬ ЗАНОВО',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10.5,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF)
                                .withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF00E5FF), width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Text(
                                hasSavedGame ? 'ПРОДОЛЖИТЬ' : 'ИГРАТЬ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Icon(Icons.play_arrow,
                                  size: 15, color: Colors.white),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStarBadge(Color color, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24, width: 0.9),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  // 3. ЭКРАН САМОЙ ИГРЫ С HUD И ПАНЕЛЬЮ УПРАВЛЕНИЯ
  Widget _buildActiveGameStack(Size viewportSize) {
    final int pUnits = _countFactionUnits(Faction.player);
    final int e1Units = _countFactionUnits(Faction.enemy1);
    final int e2Units = _countFactionUnits(Faction.enemy2);

    final int pNodes = _countFactionNodes(Faction.player);
    final int e1Nodes = _countFactionNodes(Faction.enemy1);
    final int e2Nodes = _countFactionNodes(Faction.enemy2);
    final int nNodes = _countFactionNodes(Faction.neutral);

    Rect? selectionWorldRect;
    if (_isBoxSelecting &&
        _selectionBoxStartWorld != null &&
        _selectionBoxCurrentWorld != null) {
      selectionWorldRect =
          Rect.fromPoints(_selectionBoxStartWorld!, _selectionBoxCurrentWorld!);
    }

    return Stack(
      children: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _onPointerDown(e, viewportSize),
          onPointerMove: (e) => _onPointerMove(e, viewportSize),
          onPointerUp: (e) => _onPointerUp(e, viewportSize),
          onPointerCancel: (e) {
            _activePointers.remove(e.pointer);
            if (_activePointers.isEmpty) {
              _gestureWasMultitouch = false;
              _primaryPointerId = null;
            }
            _isBoxSelecting = false;
            _selectionBoxStartWorld = null;
            _selectionBoxCurrentWorld = null;
          },
          child: CustomPaint(
            size: viewportSize,
            painter: AuraluxPainter(
              globalTime: _globalTime,
              cameraOffset: _cameraOffset,
              cameraZoom: _cameraZoom,
              bgStars: _bgStars,
              nodes: _nodes,
              units: _units,
              obstacles: _obstacles,
              wormholes: _wormholes,
              sparks: _sparks,
              waves: _waves,
              floatingTexts: _floatingTexts,
              rendezvousPoints: _rendezvousPoints,
              selectedNodes: _selectedNodes,
              selectedRendezvous: _selectedRendezvous,
              selectedUnits: _selectedUnits,
              selectionWorldRect: selectionWorldRect,
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildTopButton(
                          icon: Icons.arrow_back,
                          onTap: _returnToMenu,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _mapName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                letterSpacing: 2.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'ТАП ПО ЗВЕЗДЕ/ЧЕРВОТОЧИНЕ — ОТПРАВИТЬ • ДВОЙНОЙ ТАП — УЛУЧШИТЬ',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 8.5,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildTopStatChip(Faction.player, pNodes, pUnits),
                        const SizedBox(width: 8),
                        _buildTopStatChip(Faction.enemy1, e1Nodes, e1Units),
                        const SizedBox(width: 8),
                        _buildTopStatChip(Faction.enemy2, e2Nodes, e2Units),
                        const SizedBox(width: 8),
                        _buildTopStatChip(Faction.neutral, nNodes, 0),
                      ],
                    ),
                    Row(
                      children: [
                        _buildTopButton(
                          icon: _gameSpeed == 1.0
                              ? Icons.play_arrow
                              : Icons.fast_forward,
                          onTap: () {
                            setState(() {
                              if (_gameSpeed == 1.0) {
                                _gameSpeed = 2.0;
                              } else if (_gameSpeed == 2.0) {
                                _gameSpeed = 3.0;
                              } else {
                                _gameSpeed = 1.0;
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildTopButton(
                          icon: _isPaused ? Icons.play_arrow : Icons.pause,
                          onTap: () {
                            setState(() => _isPaused = !_isPaused);
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildTopButton(
                          icon: _audio.isMuted
                              ? Icons.volume_off
                              : Icons.volume_up,
                          onTap: () async {
                            await _audio.toggleMute();
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                if (_winner != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF070E24).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _winner == Faction.player
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFFFF1744),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_winner == Faction.player
                                    ? const Color(0xFF00E5FF)
                                    : const Color(0xFFFF1744))
                                .withValues(alpha: 0.35),
                            blurRadius: 36,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _winner == Faction.player
                                ? 'СОЗВЕЗДИЕ ЗАХВАЧЕНО!'
                                : 'ПОРАЖЕНИЕ В БИТВЕ',
                            style: TextStyle(
                              color: _winner == Faction.player
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFFFF1744),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E5FF),
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () {
                                  _openConstellationFromMenu(_currentMapType,
                                      forceRestart: true);
                                },
                                child: const Text('ЗАНОВО'),
                              ),
                              const SizedBox(width: 14),
                              OutlinedButton(
                                onPressed: _returnToMenu,
                                child: const Text('К СОЗВЕЗДИЯМ'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopStatChip(Faction f, int nodes, int units) {
    final c = factionColor(f);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            f == Faction.neutral ? '$nodes' : '$nodes ($units)',
            style: TextStyle(
              color: c,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ПРЕВЬЮ-СПИРАЛЬ ГАЛАКТИКИ В МЕНЮ
class GalaxySpiralPainter extends CustomPainter {
  final Color primaryColor;
  final double globalTime;

  GalaxySpiralPainter({
    required this.primaryColor,
    required this.globalTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.78, size.height * 0.52);

    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 45.0)
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(center, 90.0, glowPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(globalTime * 0.15);

    const int arms = 2;
    for (int a = 0; a < arms; a++) {
      final double armOffset = (pi * 2 / arms) * a;
      final armPath = Path();
      for (int i = 0; i <= 60; i++) {
        final double t = i / 60.0;
        final double ang = armOffset + t * 4.2;
        final double r = 8.0 + t * 110.0;
        final pt = Offset(cos(ang) * r, sin(ang) * r);
        if (i == 0) {
          armPath.moveTo(pt.dx, pt.dy);
        } else {
          armPath.lineTo(pt.dx, pt.dy);
        }
      }
      final armPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawPath(armPath, armPaint);
    }

    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawCircle(Offset.zero, 14.0, corePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GalaxySpiralPainter oldDelegate) => true;
}

class MenuBackgroundPainter extends CustomPainter {
  final double globalTime;
  final List<BgStar> bgStars;
  final double pageOffset;

  MenuBackgroundPainter({
    required this.globalTime,
    required this.bgStars,
    required this.pageOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, size.height / 2),
        max(size.width, size.height) * 0.9,
        [
          const Color(0xFF091024),
          const Color(0xFF030611),
          const Color(0xFF010206),
        ],
        [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    final starPaint = Paint()..style = PaintingStyle.fill;
    for (final s in bgStars) {
      final dx =
          ((s.pos.dx - pageOffset * 90 * s.depth) % size.width + size.width) %
              size.width;
      final dy = (s.pos.dy % size.height + size.height) % size.height;
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * sin(globalTime * 1.8 + s.phase));
      starPaint.color =
          Colors.white.withValues(alpha: twinkle * 0.65 * s.depth);
      canvas.drawCircle(Offset(dx, dy), s.size, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MenuBackgroundPainter oldDelegate) => true;
}

// ОТРИСОВКА ПРЕВЬЮ СОЗВЕЗДИЯ НА КАРТОЧКЕ В МЕНЮ
class ConstellationPreviewPainter extends CustomPainter {
  final ConstellationSaveData saveData;
  final double globalTime;

  ConstellationPreviewPainter({
    required this.saveData,
    required this.globalTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 6);

    double maxExtent = 600.0;
    for (final n in saveData.nodes) {
      final d = n.pos.distance + n.radius + 40.0;
      if (d > maxExtent) maxExtent = d;
    }
    for (final wh in saveData.wormholes) {
      final d = wh.pos.distance + wh.radius + 50.0;
      if (d > maxExtent) maxExtent = d;
    }
    for (final w in saveData.obstacles) {
      final d1 = w.start.distance + 30.0;
      final d2 = w.end.distance + 30.0;
      if (d1 > maxExtent) maxExtent = d1;
      if (d2 > maxExtent) maxExtent = d2;
    }

    final double fitScale =
        (min(size.width * 0.72, size.height * 0.64) / 2) / maxExtent;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(fitScale);

    // 1. Стены лабиринтов в превью
    for (final wall in saveData.obstacles) {
      final wallColor = wall.glowColor ?? const Color(0xFF00E5FF);
      final wallPaint = Paint()
        ..color = wallColor.withValues(alpha: 0.65)
        ..strokeWidth = wall.thickness * 0.8
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus;
      canvas.drawLine(wall.start, wall.end, wallPaint);

      final corePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = 1.8 / fitScale
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(wall.start, wall.end, corePaint);
    }

    // 2. Червоточины в превью
    for (final wh in saveData.wormholes) {
      final whGlow = Paint()
        ..color = const Color(0xFFE040FB).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0)
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(wh.pos, wh.radius * 1.6, whGlow);

      final whRing = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 / fitScale
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(wh.pos, wh.radius * 0.85, whRing);

      canvas.drawCircle(
          wh.pos, wh.radius * 0.52, Paint()..color = Colors.black);

      // Мини полярные джеты в превью
      for (int p = 0; p < 2; p++) {
        final ang = p == 0 ? wh.poleAngle : wh.poleAngle + pi;
        final jetEnd = wh.pos + Offset(cos(ang), sin(ang)) * 65.0;
        final jetPaint = Paint()
          ..color = const Color(0xFFE040FB).withValues(alpha: 0.75)
          ..strokeWidth = 2.4 / fitScale
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus;
        canvas.drawLine(wh.pos, jetEnd, jetPaint);
      }
    }

    // 3. Орбиты звёзд
    final orbitPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / fitScale;
    for (final node in saveData.nodes) {
      if (node.orbitCenter != null && node.orbitRadius > 0) {
        canvas.drawCircle(node.orbitCenter!, node.orbitRadius, orbitPaint);
      }
    }

    // 4. Тонкие линии созвездия
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / fitScale;

    for (int i = 0; i < saveData.nodes.length; i++) {
      for (int j = i + 1; j < saveData.nodes.length; j++) {
        final a = saveData.nodes[i].pos;
        final b = saveData.nodes[j].pos;
        if ((a - b).distance <= 260.0) {
          canvas.drawLine(a, b, linePaint);
        }
      }
    }

    // 5. Отрисовка роя частиц в превью
    for (final f in Faction.values) {
      if (f == Faction.neutral) continue;
      final pts = saveData.units
          .where((u) => !u.dead && u.faction == f)
          .map((u) => u.pos)
          .toList();
      if (pts.isEmpty) continue;
      final c = factionColor(f);
      final unitPaint = Paint()
        ..color = c.withValues(alpha: 0.65)
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus;
      canvas.drawPoints(ui.PointMode.points, pts, unitPaint);
    }

    // 6. Отрисовка звёзд и атомных орбит (начиная с 3 уровня)
    for (final node in saveData.nodes) {
      final baseColor = factionColor(node.owner);
      final pulse = sin(globalTime * 2.2 + node.pulsePhase) * 2.0;
      final r = node.radius + pulse;

      // Атомные орбиты крест-накрест для звёзд 3+ уровня
      if (node.level >= 3) {
        final double a = r * 1.75;
        final double b = r * 0.62;
        for (int o = 0; o < 2; o++) {
          final double tilt = o == 0 ? -pi / 4 : pi / 4;
          canvas.save();
          canvas.translate(node.pos.dx, node.pos.dy);
          canvas.rotate(tilt);
          final orbitRect =
              Rect.fromCenter(center: Offset.zero, width: a * 2, height: b * 2);
          final miniOrbitPaint = Paint()
            ..color = baseColor.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4 / fitScale
            ..blendMode = BlendMode.plus;
          canvas.drawOval(orbitRect, miniOrbitPaint);

          final double eAng =
              (o == 0 ? 1 : -1) * globalTime * 3.0 + o * (pi / 2);
          final electronPos = Offset(a * cos(eAng), b * sin(eAng));
          canvas.drawCircle(
              electronPos, 2.5 / fitScale, Paint()..color = Colors.white);
          canvas.restore();
        }
      }

      final glowPaint = Paint()
        ..color = baseColor.withValues(alpha: 0.45)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18.0);
      canvas.drawCircle(node.pos, r * 1.8, glowPaint);

      final corePaint = Paint()
        ..shader = ui.Gradient.radial(
          node.pos - Offset(r * 0.25, r * 0.25),
          r,
          [
            Colors.white,
            baseColor,
            Color.lerp(baseColor, Colors.black, 0.6)!,
          ],
          [0.0, 0.55, 1.0],
        );
      canvas.drawCircle(node.pos, r, corePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ConstellationPreviewPainter oldDelegate) => true;
}

class AuraluxPainter extends CustomPainter {
  final double globalTime;
  final Offset cameraOffset;
  final double cameraZoom;
  final List<BgStar> bgStars;
  final List<StarNode> nodes;
  final List<SwarmUnit> units;
  final List<ObstacleWall> obstacles;
  final List<Wormhole> wormholes;
  final List<SparkParticle> sparks;
  final List<PulseWave> waves;
  final List<FloatingText> floatingTexts;
  final List<RendezvousPoint> rendezvousPoints;
  final Set<StarNode> selectedNodes;
  final Set<RendezvousPoint> selectedRendezvous;
  final Set<SwarmUnit> selectedUnits;
  final Rect? selectionWorldRect;

  AuraluxPainter({
    required this.globalTime,
    required this.cameraOffset,
    required this.cameraZoom,
    required this.bgStars,
    required this.nodes,
    required this.units,
    required this.obstacles,
    required this.wormholes,
    required this.sparks,
    required this.waves,
    required this.floatingTexts,
    required this.rendezvousPoints,
    required this.selectedNodes,
    required this.selectedRendezvous,
    required this.selectedUnits,
    required this.selectionWorldRect,
  });

  void _drawDashedRect(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    double dashWidth = 10.0,
    double dashSpace = 7.0,
  }) {
    void drawDashedLine(Offset p1, Offset p2) {
      final totalLen = (p2 - p1).distance;
      if (totalLen <= 0.001) return;
      final dir = (p2 - p1) / totalLen;
      double cur = 0.0;
      while (cur < totalLen) {
        final end = min(cur + dashWidth, totalLen);
        canvas.drawLine(p1 + dir * cur, p1 + dir * end, paint);
        cur += dashWidth + dashSpace;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    int dashes = 20,
    double rotation = 0.0,
  }) {
    final step = (2 * pi) / dashes;
    final sweep = step * 0.55;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (int i = 0; i < dashes; i++) {
      canvas.drawArc(rect, rotation + i * step, sweep, false, paint);
    }
  }

  void _drawTexturedStarSurface(
    Canvas canvas,
    StarNode node,
    double r,
    Color baseColor,
    bool isSelected,
  ) {
    final darkPlasma = Color.lerp(baseColor, const Color(0xFF02040D), 0.65)!;
    final brightPlasma = Color.lerp(baseColor, Colors.white, 0.78)!;

    final flarePath = Path();
    const int flareSteps = 36;
    for (int i = 0; i <= flareSteps; i++) {
      final double ang = (i / flareSteps) * 2 * pi;
      final double wave1 = sin(ang * 7.0 + globalTime * 2.2 + node.pulsePhase);
      final double wave2 = cos(ang * 11.0 - globalTime * 1.6 + node.id);
      final double rad = r * (0.94 + 0.09 * wave1 + 0.05 * wave2);
      final pt = node.pos + Offset(cos(ang) * rad, sin(ang) * rad);
      if (i == 0) {
        flarePath.moveTo(pt.dx, pt.dy);
      } else {
        flarePath.lineTo(pt.dx, pt.dy);
      }
    }
    flarePath.close();

    final flarePaint = Paint()
      ..color = brightPlasma.withValues(alpha: isSelected ? 0.75 : 0.45)
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
    canvas.drawPath(flarePath, flarePaint);

    canvas.save();
    final sphereRect = Rect.fromCircle(center: node.pos, radius: r * 0.92);
    canvas.clipPath(Path()..addOval(sphereRect));

    final baseSpherePaint = Paint()
      ..shader = ui.Gradient.radial(
        node.pos - Offset(r * 0.2, r * 0.2),
        r * 1.1,
        [
          brightPlasma,
          baseColor,
          darkPlasma,
        ],
        [0.0, 0.58, 1.0],
      );
    canvas.drawCircle(node.pos, r * 0.92, baseSpherePaint);

    canvas.save();
    canvas.translate(node.pos.dx, node.pos.dy);
    canvas.rotate(globalTime * 0.2 + node.pulsePhase);
    final swirlPaint1 = Paint()
      ..shader = ui.Gradient.sweep(
        Offset.zero,
        [
          darkPlasma.withValues(alpha: 0.55),
          brightPlasma.withValues(alpha: 0.45),
          darkPlasma.withValues(alpha: 0.6),
          brightPlasma.withValues(alpha: 0.5),
          darkPlasma.withValues(alpha: 0.55),
        ],
        [0.0, 0.25, 0.5, 0.75, 1.0],
      )
      ..blendMode = BlendMode.softLight;
    canvas.drawCircle(Offset.zero, r * 0.92, swirlPaint1);
    canvas.restore();

    for (final cell in node.plasmaCells) {
      final curAngle = cell.baseAngle + globalTime * cell.angularSpeed * 0.6;
      final wobble = 1.0 + 0.15 * sin(globalTime * 2.0 + cell.phase);
      final dist = r * 0.85 * cell.radialFactor * wobble;
      final cellPos =
          node.pos + Offset(cos(curAngle) * dist, sin(curAngle) * dist);
      final cellRadius = r *
          cell.sizeFactor *
          (0.8 + 0.25 * cos(globalTime * 1.8 + cell.phase));

      if (cell.isBright) {
        final hotSpotPaint = Paint()
          ..color = Colors.white.withValues(alpha: isSelected ? 0.55 : 0.38)
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
        canvas.drawCircle(cellPos, cellRadius, hotSpotPaint);
      } else {
        final darkSpotPaint = Paint()
          ..color = darkPlasma.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
        canvas.drawCircle(cellPos, cellRadius * 0.85, darkSpotPaint);
      }
    }

    final limbShadowPaint = Paint()
      ..shader = ui.Gradient.radial(
        node.pos,
        r * 0.92,
        [
          Colors.white.withValues(alpha: 0.45),
          Colors.transparent,
          darkPlasma.withValues(alpha: 0.75),
        ],
        [0.0, 0.65, 1.0],
      );
    canvas.drawCircle(node.pos, r * 0.92, limbShadowPaint);

    canvas.restore();

    final rimPaint = Paint()
      ..color = Color.lerp(baseColor, Colors.white, 0.75)!
          .withValues(alpha: isSelected ? 0.95 : 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(node.pos, r * 0.91, rimPaint);
  }

  // АТОМНЫЕ ОРБИТЫ С ЭЛЕКТРОНАМИ КРЕСТ-НАКРЕСТ (ДЛЯ ЗВЁЗД НАЧИНАЯ С 3 УРОВНЯ)
  void _drawAtomicOrbits(Canvas canvas, StarNode node, Color baseColor) {
    final double r = node.radius;
    final double a = r * 1.76;
    final double b = r * 0.62;

    final List<double> orbitAngles = [-pi / 4, pi / 4];

    for (int i = 0; i < orbitAngles.length; i++) {
      final double tilt = orbitAngles[i];
      final double dir = i == 0 ? 1.0 : -1.0;

      canvas.save();
      canvas.translate(node.pos.dx, node.pos.dy);
      canvas.rotate(tilt);

      final orbitRect =
          Rect.fromCenter(center: Offset.zero, width: a * 2, height: b * 2);

      // Внешнее свечение трека орбиты
      final orbitGlowPaint = Paint()
        ..color = baseColor.withValues(alpha: 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
      canvas.drawOval(orbitRect, orbitGlowPaint);

      // Чёткая квантовая линия орбиты
      final orbitTrackPaint = Paint()
        ..color = Color.lerp(baseColor, Colors.white, 0.75)!
            .withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..blendMode = BlendMode.plus;
      canvas.drawOval(orbitRect, orbitTrackPaint);

      // Положение электрона на орбите
      final double electronAngle =
          dir * globalTime * 3.2 + node.id * 1.7 + i * (pi / 2);
      final double ex = a * cos(electronAngle);
      final double ey = b * sin(electronAngle);
      final electronPos = Offset(ex, ey);

      // Хвост частиц за электроном
      for (int t = 1; t <= 3; t++) {
        final double trailAng = electronAngle - dir * t * 0.12;
        final double tx = a * cos(trailAng);
        final double ty = b * sin(trailAng);
        final trailPaint = Paint()
          ..color = baseColor.withValues(alpha: 0.45 / t)
          ..blendMode = BlendMode.plus;
        canvas.drawCircle(Offset(tx, ty), 2.2 / t, trailPaint);
      }

      // Квантовое гало электрона
      final electronHaloPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
      canvas.drawCircle(electronPos, 5.5, electronHaloPaint);

      // Ядро электрона
      final electronCorePaint = Paint()
        ..color = Colors.white
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(electronPos, 2.8, electronCorePaint);

      canvas.restore();
    }
  }

  // ОТРИСОВКА СТЕН ЛАБИРИНТА
  void _drawObstacleWall(Canvas canvas, ObstacleWall wall) {
    final ab = wall.end - wall.start;
    final len = ab.distance;
    if (len < 0.001) return;

    final wallColor = wall.glowColor ?? const Color(0xFF00E5FF);

    // Внешняя энергетическая аура барьера
    final auraPaint = Paint()
      ..color = wallColor.withValues(alpha: 0.24)
      ..strokeWidth = wall.thickness + 16.0
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
    canvas.drawLine(wall.start, wall.end, auraPaint);

    // Тёмное тело космического монолита
    final bodyPaint = Paint()
      ..color = const Color(0xFF071226).withValues(alpha: 0.96)
      ..strokeWidth = wall.thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(wall.start, wall.end, bodyPaint);

    // Двойные светящиеся неоновые кромки стены
    final norm = Offset(-ab.dy, ab.dx) / len;
    final halfThick = wall.thickness * 0.45;
    final edgePaint = Paint()
      ..color = wallColor.withValues(alpha: 0.8)
      ..strokeWidth = 1.6
      ..blendMode = BlendMode.plus;
    canvas.drawLine(
        wall.start + norm * halfThick, wall.end + norm * halfThick, edgePaint);
    canvas.drawLine(
        wall.start - norm * halfThick, wall.end - norm * halfThick, edgePaint);

    // Центральный энергетический канал
    final conduitPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    canvas.drawLine(wall.start, wall.end, conduitPaint);

    // Опорные узлы на концах стены
    for (final pt in [wall.start, wall.end]) {
      final pylonGlow = Paint()
        ..color = wallColor.withValues(alpha: 0.85)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
      canvas.drawCircle(pt, wall.thickness * 0.55, pylonGlow);

      final pylonCore = Paint()
        ..color = Colors.white
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(pt, wall.thickness * 0.28, pylonCore);
    }
  }

  // ОТРИСОВКА ЧЕРВОТОЧИНЫ И ПОЛЯРНЫХ ДЖЕТОВ
  void _drawWormhole(Canvas canvas, Wormhole wh) {
    final double r = wh.radius;
    const Color wormholeAccent = Color(0xFFE040FB);
    const Color singularityCyan = Color(0xFF00E5FF);

    // 1. Пространственная аура искажения
    final ambientPaint = Paint()
      ..color = wormholeAccent.withValues(alpha: wh.isErupting ? 0.65 : 0.28)
      ..maskFilter =
          MaskFilter.blur(BlurStyle.normal, wh.isErupting ? 65.0 : 40.0)
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(wh.pos, r * (wh.isErupting ? 3.0 : 2.2), ambientPaint);

    // 2. Полярные джеты и подсветка
    for (int p = 0; p < 2; p++) {
      final double jetAngle = p == 0 ? wh.poleAngle : wh.poleAngle + pi;
      final double jetLen = wh.isErupting
          ? (340.0 + sin(globalTime * 18.0 + p) * 45.0)
          : (75.0 + sin(globalTime * 3.0 + p) * 15.0);
      final double jetSpread = wh.isErupting ? 28.0 : 10.0;

      canvas.save();
      canvas.translate(wh.pos.dx, wh.pos.dy);
      canvas.rotate(jetAngle);

      final jetPath = Path();
      jetPath.moveTo(r * 0.5, -4.0);
      jetPath.lineTo(jetLen * 0.45, -jetSpread);
      jetPath.lineTo(jetLen, 0.0);
      jetPath.lineTo(jetLen * 0.45, jetSpread);
      jetPath.lineTo(r * 0.5, 4.0);
      jetPath.close();

      // Плазменная аура джета
      final jetGlowPaint = Paint()
        ..color = (wh.isErupting ? wormholeAccent : singularityCyan)
            .withValues(alpha: wh.isErupting ? 0.75 : 0.25)
        ..maskFilter = MaskFilter.blur(
            BlurStyle.normal, wh.isErupting ? 18.0 : 8.0)
        ..blendMode = BlendMode.plus;
      canvas.drawPath(jetPath, jetGlowPaint);

      // Средний энергетический луч джета
      final jetMidPaint = Paint()
        ..color = singularityCyan.withValues(alpha: wh.isErupting ? 0.85 : 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..blendMode = BlendMode.plus;
      canvas.drawPath(jetPath, jetMidPaint);

      // Центральная яркая лазерная нить
      final jetCorePaint = Paint()
        ..color = Colors.white.withValues(alpha: wh.isErupting ? 0.95 : 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = wh.isErupting ? 3.2 : 1.4
        ..blendMode = BlendMode.plus;
      canvas.drawLine(
          Offset(r * 0.4, 0), Offset(jetLen * 0.95, 0), jetCorePaint);

      // Ромбы сжатия плазмы (Shock Diamonds) вдоль струи
      if (wh.isErupting) {
        for (double dFactor in [0.22, 0.44, 0.66, 0.84]) {
          final double dx = jetLen * dFactor;
          final double diaW = 12.0 * (1.0 - dFactor * 0.5);
          final double diaH = 22.0 * (1.0 - dFactor * 0.5);
          final diamondPath = Path()
            ..moveTo(dx - diaW, 0)
            ..lineTo(dx, -diaH * 0.5)
            ..lineTo(dx + diaW, 0)
            ..lineTo(dx, diaH * 0.5)
            ..close();
          final diamondPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..blendMode = BlendMode.plus;
          canvas.drawPath(diamondPath, diamondPaint);
        }
      }

      canvas.restore();
    }

    // 3. Вращающийся аккреционный диск
    canvas.save();
    canvas.translate(wh.pos.dx, wh.pos.dy);
    canvas.rotate(wh.spinPhase);

    final diskSweepPaint = Paint()
      ..shader = ui.Gradient.sweep(
        Offset.zero,
        [
          wormholeAccent.withValues(alpha: 0.7),
          singularityCyan.withValues(alpha: 0.9),
          Colors.white.withValues(alpha: 0.95),
          wormholeAccent.withValues(alpha: 0.5),
          wormholeAccent.withValues(alpha: 0.7),
        ],
        [0.0, 0.35, 0.5, 0.8, 1.0],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = wh.isErupting ? 14.0 : 8.5
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
    canvas.drawCircle(Offset.zero, r * 0.88, diskSweepPaint);

    for (int i = 0; i < 3; i++) {
      final double ringR = r * (0.65 + i * 0.14);
      final ringPaint = Paint()
        ..color = (i % 2 == 0 ? singularityCyan : wormholeAccent)
            .withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(Offset.zero, ringR, ringPaint);
    }
    canvas.restore();

    // 4. Индикатор набора критической массы
    final double chargeRatio =
        (wh.storedUnits / wh.criticalMass).clamp(0.0, 1.0);
    final chargeBgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(wh.pos, r + 7.0, chargeBgPaint);

    if (chargeRatio > 0 || wh.isErupting) {
      final chargeArcPaint = Paint()
        ..color = wh.isErupting
            ? Colors.white
            : Color.lerp(singularityCyan, wormholeAccent, chargeRatio)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus;
      canvas.drawArc(
        Rect.fromCircle(center: wh.pos, radius: r + 7.0),
        -pi / 2,
        (wh.isErupting ? 1.0 : chargeRatio) * 2 * pi,
        false,
        chargeArcPaint,
      );
    }

    // 5. Фотонное кольцо
    final photonRingPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(wh.pos, r * 0.56, photonRingPaint);

    // 6. Горизонт событий (чёрная дыра)
    final eventHorizonPaint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(wh.pos, r * 0.54, eventHorizonPaint);

    // Текстовая плашка статуса
    final labelText = wh.isErupting
        ? 'ДЖЕТ АКТИВЕН'
        : '${wh.storedUnits}/${wh.criticalMass}';
    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          color: wh.isErupting ? Colors.cyanAccent : Colors.white70,
          fontSize: 10.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, wh.pos + Offset(-tp.width / 2, r + 13.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        center + cameraOffset * 0.2,
        max(size.width, size.height) * 0.95,
        [
          const Color(0xFF0A122C),
          const Color(0xFF040712),
          const Color(0xFF010206),
        ],
        [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    final starPaint = Paint()..style = PaintingStyle.fill;
    for (final s in bgStars) {
      final parallaxOffset =
          center + cameraOffset * (0.15 * s.depth) + s.pos * cameraZoom * 0.5;
      final dx = (parallaxOffset.dx % size.width + size.width) % size.width;
      final dy = (parallaxOffset.dy % size.height + size.height) % size.height;
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * sin(globalTime * 1.8 + s.phase));
      starPaint.color =
          Colors.white.withValues(alpha: twinkle * 0.65 * s.depth);
      canvas.drawCircle(Offset(dx, dy), s.size * 0.85, starPaint);
    }

    canvas.save();
    canvas.translate(center.dx + cameraOffset.dx, center.dy + cameraOffset.dy);
    canvas.scale(cameraZoom);

    // Отрисовка препятствий (стен лабиринтов)
    for (final wall in obstacles) {
      _drawObstacleWall(canvas, wall);
    }

    // Отрисовка червоточин и полярных джетов
    for (final wh in wormholes) {
      _drawWormhole(canvas, wh);
    }

    // Орбиты перемещающихся звёзд
    final orbitLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final node in nodes) {
      if (node.orbitCenter != null && node.orbitRadius > 0) {
        canvas.drawCircle(node.orbitCenter!, node.orbitRadius, orbitLinePaint);
      }
    }

    // Точки сбора
    for (final rp in rendezvousPoints) {
      final isSelectedRv = selectedRendezvous.contains(rp);
      final color = factionColor(rp.faction);
      final pulseR = (isSelectedRv ? 22.0 : 18.0) + sin(rp.pulse) * 3.0;

      final rvGlow = Paint()
        ..color = color.withValues(alpha: isSelectedRv ? 0.85 : 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelectedRv ? 3.0 : 1.8
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
      canvas.drawCircle(rp.pos, pulseR, rvGlow);

      final rvDash = Paint()
        ..color = isSelectedRv ? Colors.white : color.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelectedRv ? 2.0 : 1.3;
      _drawDashedCircle(
        canvas,
        rp.pos,
        pulseR + 5,
        rvDash,
        dashes: 16,
        rotation: rp.pulse * 0.4,
      );
    }

    // Волны расширения
    for (final w in waves) {
      final wavePaint = Paint()
        ..color = w.color.withValues(alpha: (w.life * 0.8).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
      canvas.drawCircle(w.pos, w.radius, wavePaint);
    }

    // Звёзды и их атомные орбиты
    for (final node in nodes) {
      final baseColor = factionColor(node.owner);
      final isSelected = selectedNodes.contains(node);
      final pulse = sin(globalTime * 2.2 + node.pulsePhase) * 2.0;
      final r = node.radius + pulse;

      // Начиная с 3-го уровня создаётся модель атома с 2 орбитами крест-накрест
      if (node.level >= 3) {
        _drawAtomicOrbits(canvas, node, baseColor);
      }

      final ambientCorona = Paint()
        ..color = baseColor.withValues(alpha: isSelected ? 0.52 : 0.26)
        ..blendMode = BlendMode.plus
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, isSelected ? 42.0 : 28.0);
      canvas.drawCircle(
          node.pos, r * (isSelected ? 2.45 : 1.9), ambientCorona);

      final midGlow = Paint()
        ..color = baseColor.withValues(alpha: isSelected ? 0.95 : 0.72)
        ..blendMode = BlendMode.plus
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, isSelected ? 18.0 : 11.0);
      canvas.drawCircle(node.pos, r * (isSelected ? 1.45 : 1.18), midGlow);

      if (isSelected) {
        final selectedFlash = Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14.0);
        canvas.drawCircle(node.pos, r * 1.15, selectedFlash);
      }

      _drawTexturedStarSurface(canvas, node, r, baseColor, isSelected);

      if (node.owner != Faction.neutral && node.level < node.maxLevel) {
        double nextRadius;
        switch (node.level) {
          case 1:
            nextRadius = 32.0;
            break;
          case 2:
            nextRadius = 40.0;
            break;
          case 3:
          default:
            nextRadius = 48.0;
            break;
        }

        final nextRingPaint = Paint()
          ..color = baseColor.withValues(alpha: 0.32)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        canvas.drawCircle(node.pos, nextRadius, nextRingPaint);

        final upgradeProgress =
            (node.investedUnits / node.upgradeCost).clamp(0.0, 1.0);
        final displayProgress = upgradeProgress > 0
            ? upgradeProgress
            : node.spawnAccumulator.clamp(0.0, 1.0);

        final progressArcPaint = Paint()
          ..color = (upgradeProgress > 0 ? Colors.amberAccent : Colors.white)
              .withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus;
        canvas.drawArc(
          Rect.fromCircle(center: node.pos, radius: nextRadius),
          -pi / 2,
          displayProgress * 2 * pi,
          false,
          progressArcPaint,
        );
      }

      if (node.hp < 99.5) {
        final arcRect =
            Rect.fromCircle(center: node.pos, radius: node.radius + 5.0);
        final arcPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          arcRect,
          -pi / 2,
          (node.hp / 100.0) * 2 * pi,
          false,
          arcPaint,
        );
      }

      if (node.owner == Faction.player && node.level < node.maxLevel) {
        final labelText =
            'УР.${node.level} [${node.investedUnits}/${node.upgradeCost}]';
        final tp = TextPainter(
          text: TextSpan(
            text: labelText,
            style: TextStyle(
              color: node.investedUnits > 0
                  ? Colors.amberAccent
                  : (isSelected ? Colors.white : Colors.white70),
              fontSize: 11.0,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          node.pos + Offset(-tp.width / 2, node.radius + 14.0),
        );
      }

      if (isSelected) {
        final selRadius = node.radius + 12.0 + sin(globalTime * 5.0) * 1.5;
        final selDashPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;
        _drawDashedCircle(
          canvas,
          node.pos,
          selRadius,
          selDashPaint,
          dashes: 22,
          rotation: globalTime * 0.5,
        );
      }
    }

    // Отрисовка роя частиц
    for (final f in Faction.values) {
      if (f == Faction.neutral) continue;
      final fUnits = units.where((u) => !u.dead && u.faction == f).toList();
      if (fUnits.isEmpty) continue;

      final normalOffsets = <Offset>[];
      final selectedOffsets = <Offset>[];

      for (final u in fUnits) {
        bool isSelectedUnit = false;
        if (f == Faction.player) {
          if (selectedUnits.contains(u)) {
            isSelectedUnit = true;
          } else if (u.targetNode != null &&
              selectedNodes.contains(u.targetNode) &&
              (u.isOrbiting ||
                  (u.pos - u.targetNode!.pos).distance <=
                      u.targetNode!.radius + 65.0)) {
            isSelectedUnit = true;
          } else if (u.targetRendezvous != null &&
              selectedRendezvous.contains(u.targetRendezvous)) {
            isSelectedUnit = true;
          }
        }

        if (isSelectedUnit) {
          selectedOffsets.add(u.pos);
        } else {
          normalOffsets.add(u.pos);
        }
      }

      final color = factionColor(f);

      if (normalOffsets.isNotEmpty) {
        final outerAuraPaint = Paint()
          ..color = color.withValues(alpha: 0.32)
          ..strokeWidth = 13.5
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.5);
        canvas.drawPoints(ui.PointMode.points, normalOffsets, outerAuraPaint);

        final midGlowPaint = Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 7.5
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2);
        canvas.drawPoints(ui.PointMode.points, normalOffsets, midGlowPaint);

        final corePointsPaint = Paint()
          ..color = Color.lerp(color, Colors.white, 0.85)!
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus;
        canvas.drawPoints(ui.PointMode.points, normalOffsets, corePointsPaint);
      }

      if (selectedOffsets.isNotEmpty) {
        final selOuterAura = Paint()
          ..color = color.withValues(alpha: 0.65)
          ..strokeWidth = 17.5
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9.0);
        canvas.drawPoints(ui.PointMode.points, selectedOffsets, selOuterAura);

        final selMidGlow = Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..strokeWidth = 9.5
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        canvas.drawPoints(ui.PointMode.points, selectedOffsets, selMidGlow);

        final selCore = Paint()
          ..color = Colors.white
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus;
        canvas.drawPoints(ui.PointMode.points, selectedOffsets, selCore);
      }
    }

    // Искры
    for (final s in sparks) {
      final sparkAura = Paint()
        ..color = s.color.withValues(alpha: (s.life / s.maxLife) * 0.85)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      canvas.drawCircle(s.pos, s.size * 1.5, sparkAura);

      final sparkCore = Paint()
        ..color = Colors.white.withValues(alpha: (s.life / s.maxLife))
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(s.pos, s.size * 0.75, sparkCore);
    }

    // Всплывающие тексты
    for (final ft in floatingTexts) {
      final tp = TextPainter(
        text: TextSpan(
          text: ft.text,
          style: TextStyle(
            color: ft.color.withValues(alpha: ft.life.clamp(0.0, 1.0)),
            fontSize: 12.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, ft.pos - Offset(tp.width / 2, tp.height / 2));
    }

    // Рамка выделения
    if (selectionWorldRect != null) {
      final fillPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawRect(selectionWorldRect!, fillPaint);

      final borderPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      _drawDashedRect(canvas, selectionWorldRect!, borderPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AuraluxPainter oldDelegate) => true;
}
