/// An exact fraction, like Python's `Fraction`: the plan must not drift.
///
/// Pure Dart (no Flutter), so a plain `dart run` can check it against the
/// Python goldens.
library;

/// A normalised fraction `n / d`, `d > 0`.
final class Rational implements Comparable<Rational> {
  const new _(this.n, this.d);

  /// A whole number.
  factory of(int value) => Rational._(BigInt.from(value), BigInt.one);

  /// `a / b` from ints.
  factory frac(int a, int b) =>
      Rational.reduced(BigInt.from(a), BigInt.from(b));

  /// `n / d`, reduced.
  factory reduced(BigInt n, [BigInt? d]) {
    var den = d ?? BigInt.one;
    var num = n;
    if (den.isNegative) {
      den = -den;
      num = -num;
    }
    final g = num.gcd(den);
    return g <= BigInt.one
        ? Rational._(num, den)
        : Rational._(num ~/ g, den ~/ g);
  }

  /// 0.
  static final zero = Rational.of(0);

  /// Numerator.
  final BigInt n;

  /// Denominator, always positive.
  final BigInt d;

  /// Sum.
  Rational operator +(Rational o) =>
      Rational.reduced(n * o.d + o.n * d, d * o.d);

  /// Difference.
  Rational operator -(Rational o) =>
      Rational.reduced(n * o.d - o.n * d, d * o.d);

  /// Product.
  Rational operator *(Rational o) => Rational.reduced(n * o.n, d * o.d);

  /// Quotient (`o` must not be 0).
  Rational operator /(Rational o) => Rational.reduced(n * o.d, d * o.n);

  /// Negation.
  Rational operator -() => Rational._(-n, d);

  /// Less than.
  bool operator <(Rational o) => compareTo(o) < 0;

  /// Less than or equal.
  bool operator <=(Rational o) => compareTo(o) <= 0;

  /// Greater than.
  bool operator >(Rational o) => compareTo(o) > 0;

  /// Greater than or equal.
  bool operator >=(Rational o) => compareTo(o) >= 0;

  /// Whether this is exactly 0.
  bool get isZero => n == BigInt.zero;

  /// The smallest whole number not below this (Python's `math.ceil`).
  int ceil() {
    // `~/` truncates toward zero; d > 0, so only a positive remainder rounds up.
    final q = n ~/ d;
    return (n.remainder(d) > BigInt.zero ? q + BigInt.one : q).toInt();
  }

  @override
  int compareTo(Rational o) => (n * o.d).compareTo(o.n * d);

  @override
  String toString() => d == BigInt.one ? '$n' : '$n/$d';
}

/// The larger of two.
Rational maxQ(Rational a, Rational b) => a >= b ? a : b;

/// The sum of [values].
Rational sumQ(Iterable<Rational> values) =>
    values.fold(Rational.zero, (a, b) => a + b);
