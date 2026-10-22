import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'location.dart';

/// A location the user keeps at hand: the Go To popup, the Favorites
/// quick list and menu.
@immutable
class Favorite extends Equatable {
  const Favorite({required this.location, this.title});

  final Location location;

  /// A name of the user's own; the folder's name otherwise.
  final String? title;

  String get label =>
      title?.trim().isNotEmpty == true ? title!.trim() : location.name;

  Map<String, Object?> toJson() => {
    'location': location.encode(),
    if (title != null) 'title': title,
  };

  static Favorite? fromJson(Map<String, Object?> json) {
    final encoded = json['location'];
    if (encoded is! String) return null;
    final location = Location.decode(encoded);
    if (location == null) return null;
    final title = json['title'];
    return Favorite(location: location, title: title is String ? title : null);
  }

  @override
  List<Object?> get props => [location, title];
}
