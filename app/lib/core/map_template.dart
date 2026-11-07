import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';

/// A map template (backend/maps/templates/*.json). Coordinates are normalised 0..1 over the image.
class MapTemplate {
  MapTemplate({
    required this.id,
    required this.image,
    required this.aspect,
    required this.territories,
    required this.seaLinks,
    required this.bases,
  });

  final String id;
  final String image;
  final double aspect; // width / height
  final List<TerritoryShape> territories;
  final List<SeaLink> seaLinks;
  final List<int> bases;

  TerritoryShape byId(int id) => territories.firstWhere((t) => t.id == id);

  static final _cache = <String, MapTemplate>{};

  static Future<MapTemplate> load(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final raw = jsonDecode(await rootBundle.loadString('assets/maps/templates/$id.json')) as Map<String, dynamic>;
    final t = MapTemplate(
      id: raw['id'] as String,
      image: raw['image'] as String,
      aspect: (raw['aspect'] as num).toDouble(),
      territories: [
        for (final t in raw['territories'] as List)
          TerritoryShape(
            id: int.parse('${t['id']}'),
            polygon: [for (final p in t['polygon'] as List) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
            label: Offset((t['label'][0] as num).toDouble(), (t['label'][1] as num).toDouble()),
            neighbors: [for (final n in t['neighbors'] as List) (n as num).toInt()],
          ),
      ],
      seaLinks: [
        for (final s in raw['sea_links'] as List)
          SeaLink(
            (s['a'] as num).toInt(),
            (s['b'] as num).toInt(),
            Offset((s['from'][0] as num).toDouble(), (s['from'][1] as num).toDouble()),
            Offset((s['to'][0] as num).toDouble(), (s['to'][1] as num).toDouble()),
          ),
      ],
      bases: [for (final b in raw['bases'] as List) (b as num).toInt()],
    );
    _cache[id] = t;
    return t;
  }
}

class TerritoryShape {
  TerritoryShape({required this.id, required this.polygon, required this.label, required this.neighbors});
  final int id;
  final List<Offset> polygon;
  final Offset label;
  final List<int> neighbors;

  Path? _path;
  Size? _pathSize;

  /// Path scaled to [size] (cached per size: the map repaints often, the shapes never change).
  Path path(Size size) {
    if (_path != null && _pathSize == size) return _path!;
    final p = Path()..moveTo(polygon.first.dx * size.width, polygon.first.dy * size.height);
    for (final o in polygon.skip(1)) {
      p.lineTo(o.dx * size.width, o.dy * size.height);
    }
    p.close();
    _path = p;
    _pathSize = size;
    return p;
  }

  bool contains(Offset normalised) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if ((a.dy > normalised.dy) != (b.dy > normalised.dy) &&
          normalised.dx < (b.dx - a.dx) * (normalised.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }
}

class SeaLink {
  SeaLink(this.a, this.b, this.from, this.to);
  final int a, b;
  final Offset from, to;
}
