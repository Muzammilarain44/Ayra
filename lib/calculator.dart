/// Safe arithmetic expression evaluator for Ayra.
///
/// Parses and evaluates expressions with +, -, *, /, %, ^, parentheses,
/// unary minus and decimals. No `eval` — the input is tokenised and parsed
/// with a small recursive-descent parser, so a command can never run code.
library;

class Calculator {
  static double evaluate(String input) {
    final parser = _Parser(_tokenize(input));
    final value = parser.parseExpression();
    if (parser.hasMore) {
      throw const FormatException('Unexpected characters in expression');
    }
    if (value.isNaN || value.isInfinite) {
      throw const FormatException('Result is not a finite number');
    }
    return value;
  }

  /// Formats a result the way a person expects: 4, not 4.0; 2.5, not 2.5000001.
  static String format(double value) {
    if (value == value.truncateToDouble()) return value.truncate().toString();
    var text = value.toStringAsFixed(6);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  static List<_Token> _tokenize(String input) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < input.length) {
      final ch = input[i];
      if (ch == ' ' || ch == '\t') {
        i++;
        continue;
      }
      if (ch == '+' || ch == '-' || ch == '*' || ch == '/' || ch == '%' ||
          ch == '^' || ch == '(' || ch == ')') {
        tokens.add(_Token(_TokenType.op, ch));
        i++;
        continue;
      }
      if (ch == 'x' || ch == 'X' || ch == '×' || ch == '÷') {
        tokens.add(_Token(_TokenType.op, ch == '÷' ? '/' : '*'));
        i++;
        continue;
      }
      if (_isDigit(ch) || ch == '.') {
        var j = i;
        var dots = 0;
        while (j < input.length && (_isDigit(input[j]) || input[j] == '.')) {
          if (input[j] == '.') dots++;
          j++;
        }
        if (dots > 1) throw const FormatException('Bad number');
        tokens.add(_Token(_TokenType.number, input.substring(i, j)));
        i = j;
        continue;
      }
      throw FormatException('Unexpected character: $ch');
    }
    tokens.add(const _Token(_TokenType.end, ''));
    return tokens;
  }

  static bool _isDigit(String ch) =>
      ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
}

enum _TokenType { number, op, end }

class _Token {
  const _Token(this.type, this.text);
  final _TokenType type;
  final String text;
}

class _Parser {
  _Parser(this.tokens);
  final List<_Token> tokens;
  var _pos = 0;

  _Token get _current => tokens[_pos];
  bool get hasMore => _current.type != _TokenType.end;

  double parseExpression() {
    var value = parseTerm();
    while (_current.text == '+' || _current.text == '-') {
      final op = _current.text;
      _pos++;
      final rhs = parseTerm();
      value = op == '+' ? value + rhs : value - rhs;
    }
    return value;
  }

  double parseTerm() {
    var value = parseFactor();
    while (_current.text == '*' || _current.text == '/' ||
        _current.text == '%') {
      final op = _current.text;
      _pos++;
      final rhs = parseFactor();
      if (op == '*') {
        value = value * rhs;
      } else if (op == '/') {
        if (rhs == 0) throw const FormatException('Cannot divide by zero');
        value = value / rhs;
      } else {
        if (rhs == 0) throw const FormatException('Cannot divide by zero');
        value = value % rhs;
      }
    }
    return value;
  }

  double parseFactor() {
    var value = parseUnary();
    if (_current.text == '^') {
      _pos++;
      final exponent = parseFactor();
      value = _pow(value, exponent);
    }
    return value;
  }

  double parseUnary() {
    if (_current.text == '-') {
      _pos++;
      return -parseUnary();
    }
    if (_current.text == '+') {
      _pos++;
      return parseUnary();
    }
    return parsePrimary();
  }

  double parsePrimary() {
    if (_current.type == _TokenType.number) {
      final value = double.parse(_current.text);
      _pos++;
      return value;
    }
    if (_current.text == '(') {
      _pos++;
      final value = parseExpression();
      if (_current.text != ')') {
        throw const FormatException('Missing closing bracket');
      }
      _pos++;
      return value;
    }
    throw const FormatException('Expected a number');
  }

  double _pow(double base, double exponent) {
    // Integer exponents by hand; anything else goes through dart:math-free
    // repeated multiplication is wrong for fractions, so use exp/ln via
    // the standard library-free approximation: fall back to `pow` from
    // dart:math through a tiny helper (imported below).
    return _mathPow(base, exponent);
  }
}

double _mathPow(double base, double exponent) {
  // Implemented with logarithms to avoid importing dart:math in the parser
  // class itself; kept as a separate function for clarity.
  if (exponent == exponent.truncateToDouble()) {
    var result = 1.0;
    final n = exponent.truncate().abs();
    for (var i = 0; i < n; i++) {
      result *= base;
    }
    return exponent < 0 ? 1 / result : result;
  }
  // Fractional exponent: use exp(ln) identity.
  if (base <= 0) throw const FormatException('Invalid power');
  return _exp(_ln(base) * exponent);
}

double _ln(double x) {
  // Natural logarithm via the atanh series; accurate enough for a pocket
  // calculator and dependency-free.
  if (x <= 0) throw const FormatException('Invalid logarithm');
  final y = (x - 1) / (x + 1);
  final y2 = y * y;
  var term = y;
  var sum = 0.0;
  for (var n = 0; n < 60; n++) {
    sum += term / (2 * n + 1);
    term *= y2;
  }
  return 2 * sum;
}

double _exp(double x) {
  var sum = 1.0;
  var term = 1.0;
  for (var n = 1; n < 40; n++) {
    term *= x / n;
    sum += term;
  }
  return sum;
}
