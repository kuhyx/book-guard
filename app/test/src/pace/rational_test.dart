import 'package:book_guard_app/src/pace/rational.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fractions are reduced and print as n or n/d', () {
    expect('${Rational.frac(6, 4)}', '3/2');
    expect('${Rational.frac(6, 3)}', '2');
    expect('${Rational.frac(3, 5)}', '3/5');
    expect('${Rational.of(7)}', '7');
    expect('${Rational.reduced(BigInt.from(10))}', '10');
    expect(Rational.zero.isZero, isTrue);
    expect(Rational.of(1).isZero, isFalse);
  });

  test('a negative denominator moves its sign to the numerator', () {
    final q = Rational.frac(1, -2);
    expect('$q', '-1/2');
    expect(q.d, BigInt.two);
    expect('${Rational.frac(-4, -8)}', '1/2');
  });

  test('arithmetic is exact', () {
    final third = Rational.frac(1, 3);
    final sixth = Rational.frac(1, 6);
    expect('${third + sixth}', '1/2');
    expect('${third - sixth}', '1/6');
    expect('${third * sixth}', '1/18');
    expect('${third / sixth}', '2');
    expect('${-third}', '-1/3');
    expect('${sumQ([third, third, third])}', '1');
    expect(sumQ(const []).isZero, isTrue);
  });

  test('comparisons', () {
    final a = Rational.frac(1, 3);
    final b = Rational.frac(1, 2);
    expect(a < b, isTrue);
    expect(a <= a, isTrue);
    expect(b > a, isTrue);
    expect(b >= b, isTrue);
    expect(a > b, isFalse);
    expect(a.compareTo(b), lessThan(0));
    expect(maxQ(a, b), b);
    expect(maxQ(b, a), b);
  });

  test('ceil rounds toward positive infinity like Python', () {
    expect(Rational.frac(7, 2).ceil(), 4);
    expect(Rational.frac(8, 2).ceil(), 4);
    expect(Rational.frac(-7, 2).ceil(), -3);
    expect(Rational.frac(-8, 2).ceil(), -4);
    expect(Rational.zero.ceil(), 0);
  });
}
