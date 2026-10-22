/// Bindings to the Rust core.
///
/// Repositories import this package with a prefix (`as rust`) and translate
/// the generated types into `domain_models` through [`mapping.dart`]; feature
/// packages never see generated code.
library;

export 'src/backend.dart';
export 'src/mapping.dart';
export 'src/rust/api/attrs.dart';
export 'src/rust/api/events.dart';
export 'src/rust/api/files.dart';
export 'src/rust/api/find.dart';
export 'src/rust/api/listing.dart';
export 'src/rust/api/ops.dart';
export 'src/rust/api/rename.dart';
export 'src/rust/api/system.dart';
export 'src/rust/api/types.dart';
export 'src/rust/api/volume_id.dart';
export 'src/rust/frb_generated.dart' show FerryxRustLib;
export 'src/rust/api/terminal.dart';
