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
      title: 'Auralux: Constellations',
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

      const double stepSec = 2.0;
      final int bellIdx = (t / stepSec).floor();
      final double localT = t - bellIdx * stepSec;
      final double bellFreq = bellNotes[(bellIdx * 3) % bellNotes.length];
      final double bellEnv = exp(-localT * 2.6) * (1.0 - exp(-localT * 35.0));
      final double bellWave = sin(2 * pi * bellFreq * localT) +
          0.3 * sin(2 * pi * (bellFreq * 2.0) * localT);
      sample += bellWave * bellEnv * 0.14;

      double edgeFade = 1.0;
      if (t < 0.4) edgeFade = t / 0.4;
      if (t > durationSec - 0.4) edgeFade = (durationSec - t) / 0.4;
      sample *= (0.85 + 0.15 * edgeFade);

      final int pcm = (sample.clamp(-0.95, 0.95) * 32767).toInt();
      data.setInt16(44 + i * 2, pcm, Endian.little);
    }
    return data.buffer.asUint8List();
  }

  Uint8List _generateChordChimeWav(
    List<double> freqs, {
    required double durationSec,
    double volume = 0.4,
    bool arpeggio = false,
    int sampleRate = 22050,
  }) {
    final int numSamples = (durationSec * sampleRate).toInt();
    final ByteData data = ByteData(44 + numSamples * 2);
    _writeWavHeader(data, numSamples, sampleRate);

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      double sample = 0.0;
      for (int idx = 0; idx < freqs.length; idx++) {
        final double delay = arpeggio ? idx * 0.055 : 0.0;
        if (t < delay) continue;
        final double nt = t - delay;
        final double env = exp(-nt * 5.2) * (1.0 - exp(-nt * 80.0));
        final double f = freqs[idx];
        sample += (sin(2 * pi * f * nt) + 0.25 * sin(2 * pi * f * 2 * nt)) *
            env /
            sqrt(freqs.length);
      }
      final int pcm = ((sample * volume).clamp(-0.95, 0.95) * 32767).toInt();
      data.setInt16(44 + i * 2, pcm, Endian.little);
    }
    return data.buffer.asUint8List();
  }

  void _writeWavHeader(ByteData data, int numSamples, int sampleRate) {
    final int dataSize = numSamples * 2;
    final int fileSize = 36 + dataSize;
    void writeStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    data.setUint32(4, fileSize, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    data.setUint32(40, dataSize, Endian.little);
  }
}

enum Faction { neutral, player, enemy1, enemy2 }

Color factionColor(Faction f) {
  switch (f) {
    case Faction.neutral:
      return const Color(0xFF75869B);
    case Faction.player:
      return const Color(0xFF00E5FF);
    case Faction.enemy1:
      return const Color(0xFFFF1744);
    case Faction.enemy2:
      return const Color(0xFF00E676);
  }
}

enum ConstellationType {
  twinSpiral,
  ringCluster,
  binaryFront,
  supernovaCross,
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

class SwarmUnit {
  Offset pos;
  Offset vel;
  Faction faction;
  StarNode? targetNode;
  RendezvousPoint? targetRendezvous;
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
  ) {
    final int? tNodeId = json['targetNodeId'] as int?;
    final int? tRvId = json['targetRvId'] as int?;
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
    this.radius = 10.0,
    this.maxRadius = 95.0,
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

// Слепок состояния созвездия (используется и для сохранения на устройство, и для рендера превьюшек)
class ConstellationSaveData {
  final ConstellationType type;
  final List<StarNode> nodes;
  final List<RendezvousPoint> rendezvousPoints;
  final List<SwarmUnit> units;
  final Faction? winner;
  final Offset cameraOffset;
  final double cameraZoom;
  final bool isStarted;

  ConstellationSaveData({
    required this.type,
    required this.nodes,
    required this.rendezvousPoints,
    required this.units,
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

    final unitsList = (json['units'] as List)
        .map((u) =>
            SwarmUnit.fromJson(u as Map<String, dynamic>, nodeMap, rvMap))
        .toList();

    final int? winnerIdx = json['winner'] as int?;

    return ConstellationSaveData(
      type: type,
      nodes: nodesList,
      rendezvousPoints: rvList,
      units: unitsList,
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
  late Ticker _ticker;
  Duration _lastTime = Duration.zero;
  double _globalTime = 0.0;
  double _autoSaveTimer = 0.0;

  final Random _rng = Random();
  final CosmicAudioEngine _audio = CosmicAudioEngine();

  final List<BgStar> _bgStars = [];
  final List<StarNode> _nodes = [];
  final List<SwarmUnit> _units = [];
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

  // Управление главным меню и сохранёнными состояниями
  bool _inMenu = true;
  late PageController _pageController;
  int _menuPageIndex = 0;
  double _menuPageValue = 0.0;
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
    _pageController = PageController(viewportFraction: 0.68, initialPage: 0);
    _pageController.addListener(() {
      if (_pageController.hasClients && _pageController.page != null) {
        setState(() {
          _menuPageValue = _pageController.page!;
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
    _pageController.dispose();
    _ticker.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enforceFullscreen();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_inMenu) {
        _saveCurrentLevelSnapshot();
      }
      _persistStateToDisk();
    }
  }

  // Находим доступный файл во внутренней памяти приложения без сторонних плагинов
  Future<File?> _getSaveFile() async {
    final List<String> candidateDirs = [];
    try {
      // На Android в /proc/self/cmdline лежит package name приложения
      final cmdlineFile = File('/proc/self/cmdline');
      if (await cmdlineFile.exists()) {
        final bytes = await cmdlineFile.readAsBytes();
        final pkg = String.fromCharCodes(bytes.takeWhile((b) => b != 0)).trim();
        if (pkg.isNotEmpty && pkg.contains('.')) {
          candidateDirs.add('/data/user/0/$pkg/files');
          candidateDirs.add('/data/data/$pkg/files');
        }
      }
    } catch (_) {}

    candidateDirs.add(Directory.systemTemp.path);

    for (final dirPath in candidateDirs) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return File('${dir.path}/auralux_constellations_save_v1.json');
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
        'version': 1,
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

    final clonedUnits = _units
        .where((u) => !u.dead)
        .map((u) => SwarmUnit.fromJson(u.toJson(), nodeMap, rvMap))
        .toList();

    _savedConstellations[_currentMapType] = ConstellationSaveData(
      type: _currentMapType,
      nodes: clonedNodes,
      rendezvousPoints: clonedRv,
      units: clonedUnits,
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

  void _restartCurrentLevel() {
    final fresh =
        _buildInitialConstellationData(_currentMapType, markStarted: true);
    _savedConstellations[_currentMapType] = fresh;
    _applySaveDataToActiveWorld(fresh);
    _isPaused = false;
    _persistStateToDisk();
    setState(() {});
  }

  void _returnToMenu() {
    _saveCurrentLevelSnapshot();
    _persistStateToDisk();
    _clearSelection();
    _isBoxSelecting = false;
    _inMenu = true;
    setState(() {});
  }

  void _applySaveDataToActiveWorld(ConstellationSaveData data) {
    _nodes.clear();
    _units.clear();
    _sparks.clear();
    _waves.clear();
    _floatingTexts.clear();
    _rendezvousPoints.clear();
    _clearSelection();
    _selectionBoxStartWorld = null;
    _selectionBoxCurrentWorld = null;

    final clonedNodes = data.nodes
        .map((n) => StarNode.fromJson(n.toJson(), _generatePlasmaTexture()))
        .toList();
    final nodeMap = {for (final n in clonedNodes) n.id: n};

    final clonedRv = data.rendezvousPoints
        .map((r) => RendezvousPoint.fromJson(r.toJson()))
        .toList();
    final rvMap = {for (final r in clonedRv) r.id: r};

    final clonedUnits = data.units
        .where((u) => !u.dead)
        .map((u) => SwarmUnit.fromJson(u.toJson(), nodeMap, rvMap))
        .toList();

    _nodes.addAll(clonedNodes);
    _rendezvousPoints.addAll(clonedRv);
    _units.addAll(clonedUnits);

    int maxRvId = 0;
    for (final r in _rendezvousPoints) {
      if (r.id > maxRvId) maxRvId = r.id;
    }
    _rvIdCounter = maxRvId + 1;

    _winner = data.winner;
    _cameraOffset = data.cameraOffset;
    _cameraZoom = data.cameraZoom;
  }

  void _initBackground() {
    _bgStars.clear();
    for (int i = 0; i < 280; i++) {
      _bgStars.add(
        BgStar(
          Offset(
            (_rng.nextDouble() - 0.5) * 3200,
            (_rng.nextDouble() - 0.5) * 3200,
          ),
          0.15 + _rng.nextDouble() * 0.85,
          0.7 + _rng.nextDouble() * 2.2,
          _rng.nextDouble() * pi * 2,
        ),
      );
    }
  }

  List<PlasmaCell> _generatePlasmaTexture() {
    final cells = <PlasmaCell>[];
    for (int i = 0; i < 16; i++) {
      cells.add(
        PlasmaCell(
          radialFactor: 0.12 + _rng.nextDouble() * 0.65,
          baseAngle: _rng.nextDouble() * pi * 2,
          angularSpeed: (_rng.nextDouble() - 0.5) * 0.7,
          sizeFactor: 0.22 + _rng.nextDouble() * 0.28,
          phase: _rng.nextDouble() * pi * 2,
          isBright: i % 2 == 0,
        ),
      );
    }
    return cells;
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

  ConstellationSaveData _buildInitialConstellationData(
    ConstellationType type, {
    bool markStarted = false,
  }) {
    final List<StarNode> genNodes = [];
    final List<SwarmUnit> genUnits = [];
    int idCounter = 0;

    void spawnInitialUnits(StarNode node, Faction faction, int count) {
      for (int i = 0; i < count; i++) {
        double ang = _rng.nextDouble() * pi * 2;
        double dist = node.radius + 14.0 + _rng.nextDouble() * 34.0;
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
        spawnInitialUnits(node, owner, 24);
      }
    }

    switch (type) {
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
    }

    return ConstellationSaveData(
      type: type,
      nodes: genNodes,
      rendezvousPoints: [],
      units: genUnits,
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

  void _updateGame(double dt) {
    _globalTime += dt;

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

    for (final u in _units) {
      if (u.dead) continue;

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

      final target = u.targetNode;
      if (target == null) continue;

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
          u.isOrbiting &&
          !u.isUpgradingTarget) {
        continue;
      }

      u.targetNode = target;
      u.targetRendezvous = null;
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

    if (_gestureWasMultitouch || event.pointer != _primaryPointerId) return;

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
    final now = DateTime.now();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize =
              Size(constraints.maxWidth, constraints.maxHeight);

          if (_inMenu) {
            return _buildConstellationMenu(viewportSize);
          }
          return _buildActiveGameStack(viewportSize);
        },
      ),
    );
  }

  // ГЛАВНОЕ МЕНЮ С КАРУСЕЛЬЮ СОЗВЕЗДИЙ И АКТУАЛЬНЫМИ ПРЕВЬЮ
  Widget _buildConstellationMenu(Size viewportSize) {
    return Stack(
      children: [
        CustomPaint(
          size: viewportSize,
          painter: MenuBackgroundPainter(
            globalTime: _globalTime,
            bgStars: _bgStars,
            pageOffset: _menuPageValue,
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
                          'AURALUX: CONSTELLATIONS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            letterSpacing: 4.5,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'СВАЙПАЙТЕ ВЛЕВО/ВПРАВО  •  НАЖМИТЕ НА СОЗВЕЗДИЕ ДЛЯ ИГРЫ',
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
                  controller: _pageController,
                  itemCount: ConstellationType.values.length,
                  onPageChanged: (idx) {
                    HapticFeedback.selectionClick();
                    setState(() => _menuPageIndex = idx);
                  },
                  itemBuilder: (context, index) {
                    final type = ConstellationType.values[index];
                    final saveData = _savedConstellations[type] ??
                        _buildInitialConstellationData(type);

                    final double delta = (_menuPageValue - index).abs();
                    final double scale = (1.0 - delta * 0.14).clamp(0.84, 1.0);
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
                    ConstellationType.values.length,
                    (i) {
                      final active = i == _menuPageIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: active ? 24 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF00E5FF)
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
              // Живое превью звёзд созвездия (показывает актуальное сохранённое состояние)
              Positioned.fill(
                child: CustomPaint(
                  painter: ConstellationPreviewPainter(
                    saveData: saveData,
                    globalTime: _globalTime,
                  ),
                ),
              ),
              // Верхняя информационная плашка карточки
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
              // Нижняя панель карточки с балансом звёзд и кнопками «Играть / Заново»
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
                                color: const Color(0xFF00E5FF), width: 1.1),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.play_arrow,
                                  size: 15, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                hasSavedGame && winner == null
                                    ? 'ПРОДОЛЖИТЬ'
                                    : 'ИГРАТЬ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
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
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 5),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ЭКРАН АКТИВНОЙ ИГРЫ
  Widget _buildActiveGameStack(Size viewportSize) {
    final playerUnits = _countFactionUnits(Faction.player);
    final enemy1Units = _countFactionUnits(Faction.enemy1);
    final enemy2Units = _countFactionUnits(Faction.enemy2);
    final totalUnits = max(1, playerUnits + enemy1Units + enemy2Units);

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
              children: [
                Row(
                  children: [
                    _buildTopButton(
                      icon: Icons.grid_view_rounded,
                      label: 'СОЗВЕЗДИЯ',
                      onTap: _returnToMenu,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _mapName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 6,
                          child: Row(
                            children: [
                              Expanded(
                                flex:
                                    max(1, (playerUnits * 100 ~/ totalUnits)),
                                child: Container(
                                    color: factionColor(Faction.player)),
                              ),
                              Expanded(
                                flex:
                                    max(1, (enemy1Units * 100 ~/ totalUnits)),
                                child: Container(
                                    color: factionColor(Faction.enemy1)),
                              ),
                              Expanded(
                                flex:
                                    max(1, (enemy2Units * 100 ~/ totalUnits)),
                                child: Container(
                                    color: factionColor(Faction.enemy2)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildTopButton(
                      icon: _audio.isMuted
                          ? Icons.volume_off
                          : Icons.volume_up,
                      onTap: () async {
                        await _audio.toggleMute();
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildTopButton(
                      label: '${_gameSpeed.toStringAsFixed(0)}x',
                      onTap: () {
                        setState(() {
                          _gameSpeed = _gameSpeed == 1.0
                              ? 2.0
                              : (_gameSpeed == 2.0 ? 3.0 : 1.0);
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildTopButton(
                      icon: _isPaused ? Icons.play_arrow : Icons.pause,
                      onTap: () {
                        setState(() => _isPaused = !_isPaused);
                        _saveCurrentLevelSnapshot();
                        _persistStateToDisk();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildTopButton(
                      icon: Icons.refresh,
                      label: 'ЗАНОВО',
                      onTap: _restartCurrentLevel,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 14,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'СИНИЕ: $playerUnits   |   КРАСНЫЕ: $enemy1Units   |   ЗЕЛЕНЫЕ: $enemy2Units',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    letterSpacing: 1.4,
                  ),
                ),
                const Text(
                  'РАМКА: ВЫДЕЛИТЬ  •  ТАП В КОСМОС/ЗВЕЗДУ: ОТПРАВИТЬ  •  2x ТАП: ВТЯНУТЬ В РОСТ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_winner != null)
          Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _winner == Faction.player
                        ? 'СОЗВЕЗДИЕ ЗАХВАЧЕНО'
                        : 'СОЗВЕЗДИЕ ПОТЕРЯНО',
                    style: TextStyle(
                      color: factionColor(_winner!),
                      fontSize: 28,
                      letterSpacing: 5,
                      fontWeight: FontWeight.w300,
                      shadows: [
                        Shadow(
                          color: factionColor(_winner!),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                        ),
                        onPressed: _restartCurrentLevel,
                        child: const Text(
                          'ИГРАТЬ ЗАНОВО',
                          style: TextStyle(
                            color: Colors.white,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: factionColor(_winner!)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 14,
                          ),
                        ),
                        onPressed: _returnToMenu,
                        child: const Text(
                          'К СОЗВЕЗДИЯМ',
                          style: TextStyle(
                            color: Colors.white,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopButton({
    IconData? icon,
    String? label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 15, color: Colors.white70),
            if (icon != null && label != null) const SizedBox(width: 5),
            if (label != null)
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ФОН ГЛАВНОГО МЕНЮ
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
    final center = Offset(size.width / 2, size.height / 2);
    final bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        center + Offset(-pageOffset * 60.0, 0),
        max(size.width, size.height) * 0.9,
        [
          const Color(0xFF0B1536),
          const Color(0xFF040712),
          const Color(0xFF010206),
        ],
        [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    final starPaint = Paint()..style = PaintingStyle.fill;
    for (final s in bgStars) {
      final parallax = Offset(-pageOffset * 120.0 * s.depth, 0);
      final pos = center + parallax + s.pos * 0.35;
      final dx = (pos.dx % size.width + size.width) % size.width;
      final dy = (pos.dy % size.height + size.height) % size.height;
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * sin(globalTime * 1.8 + s.phase));
      starPaint.color = Colors.white.withValues(alpha: twinkle * 0.6 * s.depth);
      canvas.drawCircle(Offset(dx, dy), s.size * 0.85, starPaint);
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

    final double fitScale =
        (min(size.width * 0.72, size.height * 0.64) / 2) / maxExtent;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(fitScale);

    // Орбиты
    final orbitPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / fitScale;
    for (final node in saveData.nodes) {
      if (node.orbitCenter != null && node.orbitRadius > 0) {
        canvas.drawCircle(node.orbitCenter!, node.orbitRadius, orbitPaint);
      }
    }

    // Тонкие линии созвездия между ближайшими звёздами
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

    // Отрисовка роя частиц (актуальное состояние)
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

    // Отрисовка самих звёзд в превью
    for (final node in saveData.nodes) {
      final baseColor = factionColor(node.owner);
      final pulse = sin(globalTime * 2.2 + node.pulsePhase) * 2.0;
      final r = node.radius + pulse;

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

    final orbitLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final node in nodes) {
      if (node.orbitCenter != null && node.orbitRadius > 0) {
        canvas.drawCircle(node.orbitCenter!, node.orbitRadius, orbitLinePaint);
      }
    }

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

    for (final w in waves) {
      final wavePaint = Paint()
        ..color = w.color.withValues(alpha: (w.life * 0.8).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
      canvas.drawCircle(w.pos, w.radius, wavePaint);
    }

    for (final node in nodes) {
      final baseColor = factionColor(node.owner);
      final isSelected = selectedNodes.contains(node);
      final pulse = sin(globalTime * 2.2 + node.pulsePhase) * 2.0;
      final r = node.radius + pulse;

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

        final selCorePaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 4.8
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus;
        canvas.drawPoints(ui.PointMode.points, selectedOffsets, selCorePaint);
      }
    }

    for (final s in sparks) {
      final alpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      final sparkGlow = Paint()
        ..color = s.color.withValues(alpha: alpha * 0.7)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
      canvas.drawCircle(s.pos, s.size * alpha * 2.0, sparkGlow);

      final sparkCore = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(s.pos, s.size * alpha * 0.9, sparkCore);
    }

    if (selectionWorldRect != null) {
      final fillPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.035)
        ..style = PaintingStyle.fill;
      canvas.drawRect(selectionWorldRect!, fillPaint);

      final dashPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / cameraZoom;

      _drawDashedRect(
        canvas,
        selectionWorldRect!,
        dashPaint,
        dashWidth: 9.0 / cameraZoom,
        dashSpace: 6.0 / cameraZoom,
      );
    }

    for (final ft in floatingTexts) {
      final tp = TextPainter(
        text: TextSpan(
          text: ft.text,
          style: TextStyle(
            color: ft.color.withValues(alpha: ft.life.clamp(0.0, 1.0)),
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, ft.pos - Offset(tp.width / 2, tp.height / 2));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AuraluxPainter oldDelegate) => true;
}
