import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_flow/mesh_flow.dart';

/// 带硬约束的搜索：
///   1) 必须真有刀锋：minDet ≤ 0.045
///   2) 不许压右边界：强压缩带落在 u>0.95 的行 ≤ 15%
///   3) 落点偏右但不贴边：强压缩带中位 u ∈ [0.64, 0.80]
///   4) 刀锋要有一定纵向覆盖：cov ≥ 0.28
void main() {
  test('带约束重搜', () {
    // 基线复核：#17 应当同时满足 1/2/3/4
    final base = _m(kTerrainPresets[17].p, kTerrainPresets[17].r, 96);
    // ignore: avoid_print
    print('基线 #17  中位u=${base.medu.toStringAsFixed(3)} cov=${(base.cov * 100).toStringAsFixed(0)}% '
        'minDet=${base.minDet.toStringAsFixed(3)} 贴边=${(base.border * 100).toStringAsFixed(0)}%');

    final rnd = math.Random(77531);
    final pool = <_C>[];

    for (int i = 0; i < 26000; ++i) {
      final double cx = 0.58 + rnd.nextDouble() * 0.34;
      final double cy = 0.58 + rnd.nextDouble() * 0.34;
      final double s4 = ((cx - 0.5) / 0.36).clamp(-0.99, 0.99);
      final double s5 = ((cy - 0.5) / 0.36).clamp(-0.99, 0.99);
      final double p4 = rnd.nextBool() ? math.asin(s4) : math.pi - math.asin(s4);
      final double p5 = rnd.nextBool() ? math.asin(s5) : math.pi - math.asin(s5);

      double sr(double lo, double hi) => lo + rnd.nextDouble() * (hi - lo);

      final p = [
        rnd.nextDouble() * 2 * math.pi,
        rnd.nextDouble() * 2 * math.pi,
        rnd.nextDouble() * 2 * math.pi,
        rnd.nextDouble() * 2 * math.pi,
        p4,
        p5,
      ];
      final r = [
        sr(-1, 1), sr(-1, 1), sr(-1, 1),
        (rnd.nextBool() ? 1 : -1) * sr(0.35, 0.95),
        (rnd.nextBool() ? 1 : -1) * sr(0.25, 0.90),
        sr(-1, 1), sr(-1, 1), sr(-1, 1),
        sr(-1, 1), sr(-1, 1), sr(-1, 1), sr(-1, 1),
      ];

      final s = _m(p, r, 48);
      if (s.minDet > 0.045) continue;
      if (s.border > 0.15) continue;
      if (s.medu < 0.62 || s.medu > 0.82) continue;
      if (s.cov < 0.28) continue;
      pool.add(_C(p, r, s));
    }

    // ignore: avoid_print
    print('命中 ${pool.length} 个');

    // 按目标落点分成 4 档，每档取落点最靠中的 3 个
    const targets = [0.66, 0.70, 0.74, 0.78];
    final buf = StringBuffer();
    for (final t in targets) {
      final sorted = pool.toList()
        ..sort((a, b) => (a.s.medu - t).abs().compareTo((b.s.medu - t).abs()));
      buf.writeln('=== target u=$t');
      final picked = <_C>[];
      for (final c in sorted) {
        if (picked.any((k) =>
            (k.s.medu - c.s.medu).abs() < 0.02 && (k.s.cv - c.s.cv).abs() < 0.08)) {
          continue;
        }
        picked.add(c);
        if (picked.length == 3) break;
      }
      for (final c in picked) {
        final s = _m(c.p, c.r, 96);
        final f = (double x) => x.toStringAsFixed(2);
        buf.writeln('  u=${s.medu.toStringAsFixed(3)} v=${s.cv.toStringAsFixed(3)} '
            'cov=${(s.cov * 100).toStringAsFixed(0)}% minDet=${s.minDet.toStringAsFixed(3)} '
            '贴边=${(s.border * 100).toStringAsFixed(0)}% p10=${s.p10.toStringAsFixed(2)} '
            'p90=${s.p90.toStringAsFixed(2)}');
        buf.writeln('      p: [${c.p.map((e) => e.toStringAsFixed(2)).join(', ')}],');
        buf.writeln('      r: [${c.r.map((e) => e.toStringAsFixed(2)).join(', ')}],');
      }
    }
    // ignore: avoid_print
    print(buf.toString());
    expect(pool, isNotEmpty);
  });
}

class _C {
  _C(this.p, this.r, this.s);
  final List<double> p;
  final List<double> r;
  final _M s;
}

class _M {
  _M(this.medu, this.cv, this.cov, this.minDet, this.border, this.p10, this.p90);
  final double medu, cv, cov, minDet, border, p10, p90;
}

_M _m(List<double> p, List<double> r, int n) {
  const double kPi = math.pi;
  const double kStrong = 0.05;
  final double cx = 0.5 + 0.36 * math.sin(p[4]);
  final double cy = 0.5 + 0.36 * math.sin(p[5]);

  final us = <double>[];
  final vs = <double>[];
  double minDet = 1e9;

  for (int yi = 0; yi <= n; ++yi) {
    final double v = yi / n;
    double rowMin = 1e9;
    double rowU = 0;
    for (int xi = 0; xi <= n; ++xi) {
      final double u = xi / n;
      final double det = _det(u, v, p, r, cx, cy, kPi);
      if (det < minDet) minDet = det;
      if (det < rowMin) {
        rowMin = det;
        rowU = u;
      }
    }
    if (rowMin < kStrong) {
      us.add(rowU);
      vs.add(v);
    }
  }
  if (us.isEmpty) return _M(0, 0, 0, minDet, 1, 0, 0);
  final sorted = us.toList()..sort();
  final medu = sorted[sorted.length ~/ 2];
  final p10 = sorted[(sorted.length * 0.1).floor()];
  final p90 = sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
  final border = us.where((e) => e > 0.95).length / us.length;
  final cv = vs.reduce((a, b) => a + b) / vs.length;
  return _M(medu, cv, us.length / (n + 1), minDet, border, p10, p90);
}

double _det(double u, double v, List<double> p, List<double> r, double cx, double cy, double kPi) {
  final double m1 = math.sin(kPi * u) * math.sin(kPi * v);
  final double m2 = math.sin(2 * kPi * u) * math.sin(kPi * v);
  final double m3 = math.sin(kPi * u) * math.sin(2 * kPi * v);
  final double m4 = math.sin(2 * kPi * u) * math.sin(2 * kPi * v);
  final double m1u = kPi * math.cos(kPi * u) * math.sin(kPi * v);
  final double m1v = kPi * math.sin(kPi * u) * math.cos(kPi * v);
  final double m2u = 2 * kPi * math.cos(2 * kPi * u) * math.sin(kPi * v);
  final double m2v = kPi * math.sin(2 * kPi * u) * math.cos(kPi * v);
  final double m3u = kPi * math.cos(kPi * u) * math.sin(2 * kPi * v);
  final double m3v = 2 * kPi * math.sin(kPi * u) * math.cos(2 * kPi * v);
  final double m4u = 2 * kPi * math.cos(2 * kPi * u) * math.sin(2 * kPi * v);
  final double m4v = 2 * kPi * math.sin(2 * kPi * u) * math.cos(2 * kPi * v);

  final double t0 = _tanh(6 * (v - 0.5 - 0.30 * math.sin(p[0])));
  final double t1 = _tanh(6 * ((u + v) * 0.7 - 0.7 - 0.33 * math.sin(p[1])));
  final double t2 = _tanh(6 * (v - 0.5 - 0.30 * math.sin(p[2])));
  final double t3 = _tanh(6 * ((u - v) * 0.7 - 0.7 + 0.33 * math.sin(p[3])));
  final double d0 = 6 * (1 - t0 * t0);
  final double d1 = 6 * (1 - t1 * t1);
  final double d2 = 6 * (1 - t2 * t2);
  final double d3 = 6 * (1 - t3 * t3);

  final double tx = _tanh(6 * (u - cx));
  final double ty = _tanh(6 * (u - cy));
  final double fx = 0.10 * r[3] * tx;
  final double fy = 0.12 * r[4] * ty;
  final double fxu = 0.10 * r[3] * 6 * (1 - tx * tx);
  final double fyu = 0.12 * r[4] * 6 * (1 - ty * ty);

  final double dxu = 0.12 * (r[0] * m1u + r[1] * m2u + r[2] * m4u) +
      0.10 * r[8] * t0 * m1u +
      0.06 * r[9] * (d1 * 0.7 * m1 + t1 * m1u) +
      fxu * m1 + fx * m1u;
  final double dxv = 0.12 * (r[0] * m1v + r[1] * m2v + r[2] * m4v) +
      0.10 * r[8] * (d0 * m1 + t0 * m1v) +
      0.06 * r[9] * (d1 * 0.7 * m1 + t1 * m1v) +
      fx * m1v;
  final double dyu = 0.12 * (r[5] * m1u + r[6] * m3u + r[7] * m4u) +
      0.12 * r[10] * t2 * m1u +
      0.06 * r[11] * (d3 * 0.7 * m1 + t3 * m1u) +
      fyu * m1 + fy * m1u;
  final double dyv = 0.12 * (r[5] * m1v + r[6] * m3v + r[7] * m4v) +
      0.12 * r[10] * (d2 * m1 + t2 * m1v) +
      0.06 * r[11] * (d3 * -0.7 * m1 + t3 * m1v) +
      fy * m1v;

  return (1 + dxu) * (1 + dyv) - dxv * dyu;
}

double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
