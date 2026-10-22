import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// What `yy` or `dd` took: the paths, and whether `p` moves or copies
/// them. One for the window, so rows taken in one panel are put in the
/// other.
@immutable
class VimRegister extends Equatable {
  const VimRegister({required this.paths, required this.move});

  final List<String> paths;
  final bool move;

  @override
  List<Object?> get props => [paths, move];
}
