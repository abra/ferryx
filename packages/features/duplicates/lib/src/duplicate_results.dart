part of 'duplicates_cubit.dart';

// Persistent AVL tree: subtree counts index both groups and flattened rows.
class _Node {
  _Node(this.value, this.sequence, [this.left, this.right])
    : height = 1 + _max(left?.height ?? 0, right?.height ?? 0),
      count = 1 + (left?.count ?? 0) + (right?.count ?? 0),
      rowCount =
          1 +
          value.files.length +
          (left?.rowCount ?? 0) +
          (right?.rowCount ?? 0);
  final DuplicateGroup value;
  final int sequence;
  final _Node? left, right;
  final int height, count, rowCount;
}

int _max(int a, int b) => a > b ? a : b;
int _compare(DuplicateGroup a, int seq, _Node b) {
  final order = b.value.wasted.compareTo(a.wasted);
  return order != 0 ? order : seq.compareTo(b.sequence);
}

_Node _insert(_Node? n, DuplicateGroup value, int seq) {
  if (n == null) return _Node(value, seq);
  var left = n.left, right = n.right;
  if (_compare(value, seq, n) < 0) {
    left = _insert(left, value, seq);
  } else {
    right = _insert(right, value, seq);
  }
  n = _Node(n.value, n.sequence, left, right);
  final balance = (left?.height ?? 0) - (right?.height ?? 0);
  if (balance > 1) {
    var l = left!;
    if ((l.left?.height ?? 0) < (l.right?.height ?? 0)) {
      final r = l.right!;
      l = _Node(
        r.value,
        r.sequence,
        _Node(l.value, l.sequence, l.left, r.left),
        r.right,
      );
    }
    return _Node(
      l.value,
      l.sequence,
      l.left,
      _Node(n.value, n.sequence, l.right, right),
    );
  }
  if (balance < -1) {
    var r = right!;
    if ((r.right?.height ?? 0) < (r.left?.height ?? 0)) {
      final l = r.left!;
      r = _Node(
        l.value,
        l.sequence,
        l.left,
        _Node(r.value, r.sequence, l.right, r.right),
      );
    }
    return _Node(
      r.value,
      r.sequence,
      _Node(n.value, n.sequence, left, r.left),
      r.right,
    );
  }
  return n;
}

class _Groups extends ListBase<DuplicateGroup> {
  _Groups(this.root);
  final _Node? root;
  @override
  int get length => root?.count ?? 0;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  void operator []=(int index, DuplicateGroup value) =>
      throw UnsupportedError('immutable');
  @override
  Iterator<DuplicateGroup> get iterator => _inOrder(root).iterator;

  static Iterable<DuplicateGroup> _inOrder(_Node? root) sync* {
    final stack = <_Node>[];
    var node = root;
    while (node != null || stack.isNotEmpty) {
      while (node != null) {
        stack.add(node);
        node = node.left;
      }
      node = stack.removeLast();
      yield node.value;
      node = node.right;
    }
  }

  @override
  DuplicateGroup operator [](int index) {
    RangeError.checkValidIndex(index, this);
    var n = root!;
    while (true) {
      final count = n.left?.count ?? 0;
      if (index < count) {
        n = n.left!;
      } else if (index == count) {
        return n.value;
      } else {
        index -= count + 1;
        n = n.right!;
      }
    }
  }
}

class _Rows extends ListBase<DuplicateRow> {
  _Rows(this.root);
  final _Node? root;
  @override
  int get length => root?.rowCount ?? 0;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  void operator []=(int index, DuplicateRow value) =>
      throw UnsupportedError('immutable');
  (_Node, int, int) locate(int index) {
    RangeError.checkValidIndex(index, this);
    var n = root!;
    var group = 0;
    while (true) {
      final leftRows = n.left?.rowCount ?? 0;
      if (index < leftRows) {
        n = n.left!;
        continue;
      }
      group += n.left?.count ?? 0;
      index -= leftRows;
      if (index <= n.value.files.length) return (n, group, index);
      index -= 1 + n.value.files.length;
      group++;
      n = n.right!;
    }
  }

  @override
  DuplicateRow operator [](int index) {
    final (_, group, offset) = locate(index);
    return offset == 0 ? GroupRow(group) : FileRow(group, offset - 1);
  }

  int? movedIndex(_Node old, int offset) {
    var n = root;
    var index = 0;
    while (n != null) {
      final c = _compare(old.value, old.sequence, n);
      if (c < 0) {
        n = n.left;
      } else if (c > 0) {
        index += (n.left?.rowCount ?? 0) + 1 + n.value.files.length;
        n = n.right;
      } else {
        return index + (n.left?.rowCount ?? 0) + offset;
      }
    }
    return null;
  }
}
