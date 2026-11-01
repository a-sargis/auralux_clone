import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
        scaffoldBackgroundColor: const Color(0xFF03050C),
      ),
      home: const GameScreen(),
    );
  }
}

enum Faction { neutral, player, enemy1, enemy2 }

Color factionColor(Faction f) {
  switch (f) {
    case Faction.neutral:
      return const Color(0xFF8899AC);
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

class BgStar {
  Offset pos;
  double depth;
  double size;
  double phase;
  BgStar(this.pos, this.depth, this.size, this.phase);
}

class StarNode {
  final int id;
  Offset pos;
  Faction owner;
  int level;
  final int maxLevel;
  double hp;
  Faction capturingFaction = Faction.neutral;
  double pulsePhase;
  double spawnAccumulator = 0.0;
  double orbitRadius;
  double orbitSpeed;
  double orbitAngle;
  Offset? orbitCenter;

  StarNode({
    required this.id,
    required this.pos,
    required this.owner,
    this.level = 1,
    this.maxLevel = 3,
    this.hp = 100.0,
    required this.pulsePhase,
    this.orbitCenter,
    this.orbitRadius = 0.0,
    this.orbitSpeed = 0.0,
    this.orbitAngle = 0.0,
  });

  double get radius => 22.0 + level * 4.0;
  int get upgradeCost => level * 30;
  double get productionRate => owner == Faction.neutral ? 0.0 : (1.3 + level * 1.15);
}

class SwarmUnit {
  Offset pos;
  Offset vel;
  Faction faction;
  StarNode targetNode;
  bool isOrbiting;
  double orbitAngle;
  double orbitDist;
  double speed;
  double phase;
  bool dead = false;

  SwarmUnit({
    required this.pos,
    required this.vel,
    required this.faction,
    required this.targetNode,
    this.isOrbiting = true,
    required this.orbitAngle,
    required this.orbitDist,
    required this.speed,
    required this.phase,
  });
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

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  Duration _lastTime = Duration.zero;
  double _globalTime = 0.0;

  final Random _rng = Random();

  final List<BgStar> _bgStars = [];
  final List<StarNode> _nodes = [];
  final List<SwarmUnit> _units = [];
  final List<SparkParticle> _sparks = [];
  final List<PulseWave> _waves = [];

  final Set<StarNode> _selectedNodes = {};
  Offset? _dragCurrentWorldPos;
  StarNode? _hoveredTargetNode;

  Offset _cameraOffset = Offset.zero;
  double _cameraZoom = 0.65;
  Offset _startFocalPoint = Offset.zero;
  Offset _startCameraOffset = Offset.zero;
  double _startZoom = 0.65;
  bool _isDraggingSelection = false;

  ConstellationType _currentMapType = ConstellationType.twinSpiral;
  String _mapName = 'TWIN SPIRAL';
  double _aiTimer = 0.0;
  double _gameSpeed = 1.0;
  bool _isPaused = false;
  Faction? _winner;

  @override
  void initState() {
    super.initState();
    _initBackground();
    _generateConstellation(_currentMapType);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _initBackground() {
    _bgStars.clear();
    for (int i = 0; i < 260; i++) {
      _bgStars.add(
        BgStar(
          Offset(
            (_rng.nextDouble() - 0.5) * 3200,
            (_rng.nextDouble() - 0.5) * 3200,
          ),
          0.15 + _rng.nextDouble() * 0.85,
          0.7 + _rng.nextDouble() * 2.1,
          _rng.nextDouble() * pi * 2,
        ),
      );
    }
  }

  void _generateConstellation(ConstellationType type) {
    _nodes.clear();
    _units.clear();
    _sparks.clear();
    _waves.clear();
    _selectedNodes.clear();
    _winner = null;
    _currentMapType = type;

    int idCounter = 0;

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
      );
      _nodes.add(node);

      if (owner != Faction.neutral) {
        _spawnUnitsInstant(node, owner, 28);
      }
    }

    switch (type) {
      case ConstellationType.twinSpiral:
        _mapName = 'ANDROMEDA VORTEX';
        addNode(Offset.zero, Faction.neutral, level: 0, hp: 90);

        const int arms = 3;
        const int nodesPerArm = 4;
        for (int a = 0; a < arms; a++) {
          double baseAngle = (2 * pi / arms) * a;
          for (int i = 1; i <= nodesPerArm; i++) {
            double dist = i * 155.0;
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
              orbitSpeed: (i % 2 == 0 ? 1 : -1) * (0.04 / i),
              orbitAngle: angle,
            );
          }
        }
        break;

      case ConstellationType.ringCluster:
        _mapName = 'ORION RING';
        addNode(Offset.zero, Faction.neutral, level: 0, hp: 85);

        for (int i = 0; i < 6; i++) {
          double ang = (2 * pi / 6) * i;
          double r = 210.0;
          addNode(
            Offset(cos(ang) * r, sin(ang) * r),
            Faction.neutral,
            orbitCenter: Offset.zero,
            orbitRadius: r,
            orbitSpeed: 0.05,
            orbitAngle: ang,
          );
        }

        for (int i = 0; i < 9; i++) {
          double ang = (2 * pi / 9) * i;
          double r = 460.0;
          Faction f = Faction.neutral;
          if (i == 0) f = Faction.player;
          if (i == 3) f = Faction.enemy1;
          if (i == 6) f = Faction.enemy2;

          addNode(
            Offset(cos(ang) * r, sin(ang) * r),
            f,
            orbitCenter: Offset.zero,
            orbitRadius: r,
            orbitSpeed: -0.025,
            orbitAngle: ang,
          );
        }
        break;

      case ConstellationType.binaryFront:
        _mapName = 'CYGNUS BINARY';
        addNode(const Offset(0, -140), Faction.neutral, hp: 50);
        addNode(const Offset(0, 140), Faction.neutral, hp: 50);
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
        _mapName = 'PULSAR CROSS';
        addNode(Offset.zero, Faction.neutral, hp: 100);
        for (int dir = 0; dir < 4; dir++) {
          double ang = dir * (pi / 2);
          for (int step = 1; step <= 3; step++) {
            double r = step * 185.0;
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

    setState(() {});
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
          orbitAngle: ang,
          orbitDist: dist,
          speed: 95.0 + _rng.nextDouble() * 35.0,
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

    if (!_isPaused && _winner == null) {
      _updateGame(dt * _gameSpeed);
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
          node.hp = min(100.0, node.hp + 2.2 * dt);
        }
      }
    }

    for (final u in _units) {
      if (u.dead) continue;

      final target = u.targetNode;
      final toTarget = target.pos - u.pos;
      final dist = toTarget.distance;

      if (u.isOrbiting) {
        if (target.owner != u.faction) {
          u.isOrbiting = false;
        } else {
          u.orbitAngle += (0.85 + (40.0 / max(25.0, u.orbitDist))) * dt;
          double dynamicDist =
              u.orbitDist + sin(_globalTime * 2.5 + u.phase) * 5.5;
          Offset desiredPos = target.pos +
              Offset(
                cos(u.orbitAngle) * dynamicDist,
                sin(u.orbitAngle) * dynamicDist,
              );
          u.vel = (desiredPos - u.pos) * 6.5;
          u.pos += u.vel * dt;
        }
      } else {
        if (dist > target.radius + 28.0) {
          Offset dir = toTarget / dist;
          Offset perp = Offset(-dir.dy, dir.dx);
          double sway = sin(_globalTime * 5.0 + u.phase) * 0.28;
          Offset steer = (dir + perp * sway);
          steer = steer / steer.distance;

          u.vel = Offset.lerp(
            u.vel,
            steer * (u.speed * 1.35),
            min(1.0, dt * 5.0),
          )!;
          u.pos += u.vel * dt;
        } else {
          if (target.owner == u.faction && target.hp >= 99.5) {
            u.isOrbiting = true;
            u.orbitAngle =
                atan2(u.pos.dy - target.pos.dy, u.pos.dx - target.pos.dx);
            u.orbitDist = target.radius + 14.0 + _rng.nextDouble() * 34.0;
          } else {
            Offset dir = dist > 0.001 ? toTarget / dist : const Offset(1, 0);
            u.pos += dir * (u.speed * 1.45) * dt;

            if (dist <= target.radius + 4.0) {
              u.dead = true;
              _onUnitHitNode(u, target);
            }
          }
        }
      }
    }

    _handleUnitCollisions();
    _units.removeWhere((u) => u.dead);

    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel *= pow(0.18, dt).toDouble();
      s.life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);

    for (final w in _waves) {
      w.life -= dt * 1.35;
      w.radius = ui.lerpDouble(w.maxRadius, 12.0, max(0.0, w.life))!;
    }
    _waves.removeWhere((w) => w.life <= 0);

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
      node.hp = min(100.0, node.hp + 2.5);
      return;
    }

    node.hp -= 2.6;
    if (node.hp <= 0) {
      if (node.owner != Faction.neutral) {
        node.owner = Faction.neutral;
        node.level = 0;
        node.hp = 25.0;
        _selectedNodes.remove(node);
        _waves.add(
          PulseWave(pos: node.pos, color: Colors.white, maxRadius: 110),
        );
        _spawnSparks(node.pos, Colors.white, 24, speed: 150.0);
      } else {
        node.owner = unit.faction;
        node.level = 1;
        node.hp = 100.0;
        _waves.add(PulseWave(pos: node.pos, color: color, maxRadius: 130));
        _spawnSparks(node.pos, color, 32, speed: 170.0);
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
            _spawnSparks(mid, factionColor(a.faction), 4, speed: 95.0);
            _spawnSparks(mid, factionColor(b.faction), 4, speed: 95.0);
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
          life: 0.25 + _rng.nextDouble() * 0.38,
          size: 1.5 + _rng.nextDouble() * 2.2,
        ),
      );
    }
  }

  void _runAI(Faction aiFaction) {
    final myNodes = _nodes.where((n) => n.owner == aiFaction).toList();
    if (myNodes.isEmpty) return;

    for (final node in myNodes) {
      final orbiting = _units
          .where((u) =>
              !u.dead &&
              u.faction == aiFaction &&
              u.targetNode == node &&
              u.isOrbiting)
          .toList();

      if (node.level < node.maxLevel &&
          orbiting.length > node.upgradeCost + 14 &&
          _rng.nextDouble() < 0.45) {
        _upgradeNode(node, orbiting);
        continue;
      }

      if (orbiting.length > 26) {
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
          _sendUnitsFromNodes([node], bestTarget, aiFaction, ratio: 0.65);
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
    } else if (!enemiesAlive) {
      _winner = Faction.player;
    }
  }

  void _sendUnitsFromNodes(
    Iterable<StarNode> sources,
    StarNode target,
    Faction faction, {
    double ratio = 0.65,
  }) {
    int launched = 0;
    for (final src in sources) {
      if (src == target) continue;
      final available = _units
          .where((u) =>
              !u.dead &&
              u.faction == faction &&
              u.targetNode == src &&
              u.isOrbiting)
          .toList();

      int countToSend = (available.length * ratio).ceil();
      for (int i = 0; i < countToSend && i < available.length; i++) {
        available[i].targetNode = target;
        available[i].isOrbiting = false;
        launched++;
      }
    }
    if (launched > 0) {
      _waves.add(
        PulseWave(
          pos: target.pos,
          color: factionColor(faction),
          maxRadius: target.radius + 32,
        ),
      );
    }
  }

  void _upgradeNode(StarNode node, List<SwarmUnit> orbitingUnits) {
    if (node.level >= node.maxLevel) return;
    int cost = node.upgradeCost;
    if (orbitingUnits.length < cost) return;

    for (int i = 0; i < cost; i++) {
      orbitingUnits[i].dead = true;
      _spawnSparks(
        orbitingUnits[i].pos,
        factionColor(node.owner),
        2,
        speed: 50,
      );
    }
    node.level++;
    _waves.add(
      PulseWave(
        pos: node.pos,
        color: factionColor(node.owner),
        maxRadius: node.radius + 65,
      ),
    );
    _spawnSparks(node.pos, factionColor(node.owner), 26, speed: 140);
  }

  Offset _screenToWorld(Offset screenPos, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    return (screenPos - center - _cameraOffset) / _cameraZoom;
  }

  StarNode? _findNodeAtWorld(Offset worldPos, {double extraHitRadius = 22.0}) {
    for (final node in _nodes) {
      if ((node.pos - worldPos).distance <= node.radius + extraHitRadius) {
        return node;
      }
    }
    return null;
  }

  void _onScaleStart(ScaleStartDetails details, Size viewportSize) {
    _startFocalPoint = details.localFocalPoint;
    _startCameraOffset = _cameraOffset;
    _startZoom = _cameraZoom;

    if (details.pointerCount == 1) {
      final worldPos = _screenToWorld(details.localFocalPoint, viewportSize);
      final hitNode = _findNodeAtWorld(worldPos);

      if (hitNode != null && hitNode.owner == Faction.player) {
        _isDraggingSelection = true;
        if (!_selectedNodes.contains(hitNode)) {
          _selectedNodes.add(hitNode);
        }
        _dragCurrentWorldPos = worldPos;
        HapticFeedback.selectionClick();
      } else {
        _isDraggingSelection = false;
      }
    } else {
      _isDraggingSelection = false;
      _dragCurrentWorldPos = null;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size viewportSize) {
    if (details.pointerCount > 1 || !_isDraggingSelection) {
      setState(() {
        _cameraZoom = (_startZoom * details.scale).clamp(0.32, 1.65);
        _cameraOffset =
            _startCameraOffset + (details.localFocalPoint - _startFocalPoint);
      });
      return;
    }

    final worldPos = _screenToWorld(details.localFocalPoint, viewportSize);
    _dragCurrentWorldPos = worldPos;

    final hitNode = _findNodeAtWorld(worldPos, extraHitRadius: 26.0);
    if (hitNode != null) {
      if (hitNode.owner == Faction.player && !_selectedNodes.contains(hitNode)) {
        _selectedNodes.add(hitNode);
        HapticFeedback.selectionClick();
      }
      _hoveredTargetNode = hitNode;
    } else {
      _hoveredTargetNode = null;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isDraggingSelection) {
      if (_hoveredTargetNode != null) {
        _sendUnitsFromNodes(
          _selectedNodes,
          _hoveredTargetNode!,
          Faction.player,
          ratio: 0.65,
        );
        HapticFeedback.lightImpact();
        _selectedNodes.clear();
      }
    }
    _isDraggingSelection = false;
    _dragCurrentWorldPos = null;
    _hoveredTargetNode = null;
  }

  void _onTapUp(TapUpDetails details, Size viewportSize) {
    final worldPos = _screenToWorld(details.localPosition, viewportSize);
    final hitNode = _findNodeAtWorld(worldPos);

    if (hitNode == null) {
      _selectedNodes.clear();
      return;
    }

    if (_selectedNodes.isNotEmpty) {
      if (_selectedNodes.length == 1 && _selectedNodes.first == hitNode) {
        final orbiting = _units
            .where((u) =>
                !u.dead &&
                u.faction == Faction.player &&
                u.targetNode == hitNode &&
                u.isOrbiting)
            .toList();
        if (hitNode.level < hitNode.maxLevel &&
            orbiting.length >= hitNode.upgradeCost) {
          _upgradeNode(hitNode, orbiting);
          HapticFeedback.mediumImpact();
        }
      } else {
        _sendUnitsFromNodes(_selectedNodes, hitNode, Faction.player, ratio: 0.65);
        HapticFeedback.lightImpact();
        _selectedNodes.clear();
      }
    } else if (hitNode.owner == Faction.player) {
      _selectedNodes.add(hitNode);
      HapticFeedback.selectionClick();
    }
  }

  void _onDoubleTapDown(TapDownDetails details, Size viewportSize) {
    final worldPos = _screenToWorld(details.localPosition, viewportSize);
    final hitNode = _findNodeAtWorld(worldPos);

    if (hitNode != null && hitNode.owner == Faction.player) {
      _selectedNodes.clear();
      _selectedNodes.addAll(_nodes.where((n) => n.owner == Faction.player));
      HapticFeedback.heavyImpact();
    }
  }

  int _countFactionUnits(Faction f) =>
      _units.where((u) => !u.dead && u.faction == f).length;

  @override
  Widget build(BuildContext context) {
    final playerUnits = _countFactionUnits(Faction.player);
    final enemy1Units = _countFactionUnits(Faction.enemy1);
    final enemy2Units = _countFactionUnits(Faction.enemy2);
    final totalUnits = max(1, playerUnits + enemy1Units + enemy2Units);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (d) => _onScaleStart(d, viewportSize),
                onScaleUpdate: (d) => _onScaleUpdate(d, viewportSize),
                onScaleEnd: _onScaleEnd,
                onTapUp: (d) => _onTapUp(d, viewportSize),
                onDoubleTapDown: (d) => _onDoubleTapDown(d, viewportSize),
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
                    selectedNodes: _selectedNodes,
                    dragCurrentWorldPos: _dragCurrentWorldPos,
                    hoveredTargetNode: _hoveredTargetNode,
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
                          Text(
                            _mapName,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              letterSpacing: 2.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                height: 6,
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: max(1, (playerUnits * 100 ~/ totalUnits)),
                                      child: Container(color: factionColor(Faction.player)),
                                    ),
                                    Expanded(
                                      flex: max(1, (enemy1Units * 100 ~/ totalUnits)),
                                      child: Container(color: factionColor(Faction.enemy1)),
                                    ),
                                    Expanded(
                                      flex: max(1, (enemy2Units * 100 ~/ totalUnits)),
                                      child: Container(color: factionColor(Faction.enemy2)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
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
                            onTap: () => setState(() => _isPaused = !_isPaused),
                          ),
                          const SizedBox(width: 8),
                          _buildTopButton(
                            icon: Icons.auto_awesome,
                            label: 'НОВАЯ КАРТА',
                            onTap: () {
                              final nextIndex = (_currentMapType.index + 1) %
                                  ConstellationType.values.length;
                              _generateConstellation(
                                ConstellationType.values[nextIndex],
                              );
                            },
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
                        'СВАЙП ОТ ЗВЕЗДЫ — АТАКА  •  ПОВТОРНЫЙ ТАП — АПГРЕЙД  •  2x ТАП — ВСЕ',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          letterSpacing: 1.1,
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
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: factionColor(_winner!)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 14,
                            ),
                          ),
                          onPressed: () {
                            final nextIndex = (_currentMapType.index + 1) %
                                ConstellationType.values.length;
                            _generateConstellation(
                              ConstellationType.values[nextIndex],
                            );
                          },
                          child: const Text(
                            'СЛЕДУЮЩЕЕ СОЗВЕЗДИЕ',
                            style: TextStyle(
                              color: Colors.white,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
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
          color: Colors.white.withOpacity(0.06),
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

class AuraluxPainter extends CustomPainter {
  final double globalTime;
  final Offset cameraOffset;
  final double cameraZoom;
  final List<BgStar> bgStars;
  final List<StarNode> nodes;
  final List<SwarmUnit> units;
  final List<SparkParticle> sparks;
  final List<PulseWave> waves;
  final Set<StarNode> selectedNodes;
  final Offset? dragCurrentWorldPos;
  final StarNode? hoveredTargetNode;

  AuraluxPainter({
    required this.globalTime,
    required this.cameraOffset,
    required this.cameraZoom,
    required this.bgStars,
    required this.nodes,
    required this.units,
    required this.sparks,
    required this.waves,
    required this.selectedNodes,
    required this.dragCurrentWorldPos,
    required this.hoveredTargetNode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        center + cameraOffset * 0.2,
        max(size.width, size.height) * 0.9,
        [
          const Color(0xFF0A1128),
          const Color(0xFF050814),
          const Color(0xFF020308),
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
      starPaint.color = Colors.white.withOpacity(twinkle * 0.6 * s.depth);
      canvas.drawCircle(Offset(dx, dy), s.size * 0.8, starPaint);
    }

    canvas.save();
    canvas.translate(center.dx + cameraOffset.dx, center.dy + cameraOffset.dy);
    canvas.scale(cameraZoom);

    final orbitLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final node in nodes) {
      if (node.orbitCenter != null && node.orbitRadius > 0) {
        canvas.drawCircle(node.orbitCenter!, node.orbitRadius, orbitLinePaint);
      }
    }

    if (selectedNodes.isNotEmpty && dragCurrentWorldPos != null) {
      final targetPos = hoveredTargetNode?.pos ?? dragCurrentWorldPos!;
      final lineGlowPaint = Paint()
        ..color = factionColor(Faction.player).withOpacity(0.35)
        ..strokeWidth = 5.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
      final lineCorePaint = Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 1.6;

      for (final node in selectedNodes) {
        canvas.drawLine(node.pos, targetPos, lineGlowPaint);
        canvas.drawLine(node.pos, targetPos, lineCorePaint);
      }
    }

    for (final w in waves) {
      final wavePaint = Paint()
        ..color = w.color.withOpacity((w.life * 0.7).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawCircle(w.pos, w.radius, wavePaint);
    }

    for (final node in nodes) {
      final baseColor = factionColor(node.owner);
      final pulse = sin(globalTime * 2.6 + node.pulsePhase) * 2.2;
      final r = node.radius + pulse;

      final outerGlow = Paint()
        ..color = baseColor.withOpacity(0.38)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24.0);
      canvas.drawCircle(node.pos, r * 1.65, outerGlow);

      final innerGlow = Paint()
        ..color = baseColor.withOpacity(0.75)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9.0);
      canvas.drawCircle(node.pos, r * 1.05, innerGlow);

      final corePaint = Paint()
        ..color = Color.lerp(baseColor, Colors.white, 0.55)!
        ..style = PaintingStyle.fill;
      canvas.drawCircle(node.pos, r * 0.68, corePaint);

      final ringPaint = Paint()
        ..color = baseColor.withOpacity(0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      for (int lvl = 1; lvl <= node.level; lvl++) {
        canvas.drawCircle(node.pos, node.radius + 5.0 + lvl * 5.5, ringPaint);
      }

      if (node.hp < 99.5) {
        final arcRect =
            Rect.fromCircle(center: node.pos, radius: node.radius + 9.0);
        final arcPaint = Paint()
          ..color = Colors.white.withOpacity(0.9)
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

      if (selectedNodes.contains(node)) {
        final selRadius = node.radius + 18.0 + sin(globalTime * 6.0) * 2.5;
        final selGlow = Paint()
          ..color = Colors.white.withOpacity(0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
        canvas.drawCircle(node.pos, selRadius, selGlow);
      }
    }

    for (final f in Faction.values) {
      if (f == Faction.neutral) continue;
      final fUnits = units.where((u) => !u.dead && u.faction == f).toList();
      if (fUnits.isEmpty) continue;

      final offsets = fUnits.map((u) => u.pos).toList();
      final color = factionColor(f);

      final glowPointsPaint = Paint()
        ..color = color.withOpacity(0.55)
        ..strokeWidth = 8.5
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
      canvas.drawPoints(ui.PointMode.points, offsets, glowPointsPaint);

      final corePointsPaint = Paint()
        ..color = Color.lerp(color, Colors.white, 0.75)!
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus;
      canvas.drawPoints(ui.PointMode.points, offsets, corePointsPaint);
    }

    for (final s in sparks) {
      final alpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      final sparkPaint = Paint()
        ..color = s.color.withOpacity(alpha)
        ..blendMode = BlendMode.plus
        ..style = PaintingStyle.fill;
      canvas.drawCircle(s.pos, s.size * alpha, sparkPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AuraluxPainter oldDelegate) => true;
}
