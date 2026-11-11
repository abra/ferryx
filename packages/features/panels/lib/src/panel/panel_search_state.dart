import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';

/// A virtual tab's query and progress; rows remain ordinary FileEntry values
/// with a path relative to the query root as their identity.
class PanelSearchState extends Equatable {
  const PanelSearchState({
    required this.request,
    required this.generation,
    this.label,
    this.running = true,
    this.scanned = 0,
    this.capped = false,
  });
  final FindRequest request;
  final String? label;
  final int generation;
  final bool running;
  final int scanned;
  final bool capped;
  PanelSearchState copyWith({bool? running, int? scanned, bool? capped}) =>
      PanelSearchState(
        request: request,
        generation: generation,
        label: label,
        running: running ?? this.running,
        scanned: scanned ?? this.scanned,
        capped: capped ?? this.capped,
      );
  @override
  List<Object?> get props => [
    request,
    generation,
    label,
    running,
    scanned,
    capped,
  ];
}
