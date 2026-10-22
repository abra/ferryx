// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'ferryx_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class FerryxLocalizationsRu extends FerryxLocalizations {
  FerryxLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Ferryx';

  @override
  String aboutVersion(String version) {
    return 'Версия $version · macOS, Windows, Linux';
  }

  @override
  String get aboutDescription =>
      'Двухпанельный файловый менеджер для работы с клавиатуры: две панели, вкладки, фоновые операции, архивы, просмотрщик и поиск.';

  @override
  String get aboutLicense => 'Свободное ПО с открытым исходным кодом.';

  @override
  String get actionCancel => 'Отмена';

  @override
  String get actionOk => 'ОК';

  @override
  String get actionClose => 'Закрыть';

  @override
  String get actionSave => 'Сохранить';

  @override
  String get actionApply => 'Применить';

  @override
  String get actionDelete => 'Удалить';

  @override
  String get actionCopy => 'Копировать';

  @override
  String get actionMove => 'Переместить';

  @override
  String get actionRename => 'Переименовать';

  @override
  String get actionCreate => 'Создать';

  @override
  String get actionOpen => 'Открыть';

  @override
  String get actionRetry => 'Повторить';

  @override
  String get actionSkip => 'Пропустить';

  @override
  String get actionOverwrite => 'Заменить';

  @override
  String get actionKeepBoth => 'Оставить оба';

  @override
  String get actionMerge => 'Объединить';

  @override
  String get actionStop => 'Остановить';

  @override
  String get actionPause => 'Пауза';

  @override
  String get actionResume => 'Продолжить';

  @override
  String get actionSearch => 'Найти';

  @override
  String get actionAdd => 'Добавить';

  @override
  String get actionRemove => 'Убрать';

  @override
  String get actionReset => 'Сбросить';

  @override
  String get actionGo => 'Перейти';

  @override
  String get actionCompress => 'Сжать';

  @override
  String get actionSelect => 'Выделить';

  @override
  String get actionDeselect => 'Снять выделение';

  @override
  String get actionView => 'Просмотр';

  @override
  String get actionEject => 'Извлечь';

  @override
  String get actionClear => 'Очистить';

  @override
  String get actionDone => 'Готово';

  @override
  String joinedDetails(String first, String second) {
    return '$first · $second';
  }

  @override
  String get answerOverwriteAll => 'Заменить все';

  @override
  String get answerOverwriteOlderAll => 'Заменить старые';

  @override
  String get answerSkipAll => 'Пропустить все';

  @override
  String get answerKeepBothAll => 'Оставить оба для всех';

  @override
  String get answerMergeAll => 'Объединить все';

  @override
  String get errorNotFound => 'Не найдено';

  @override
  String get errorPermissionDenied => 'Нет доступа';

  @override
  String get errorAlreadyExists => 'Уже существует';

  @override
  String get errorNotADirectory => 'Это не папка';

  @override
  String get errorIsADirectory => 'Это папка';

  @override
  String get errorNotEmpty => 'Папка не пуста';

  @override
  String get errorUnsupported => 'Здесь недоступно';

  @override
  String get errorCancelled => 'Отменено';

  @override
  String get errorInvalidName => 'Недопустимое имя';

  @override
  String get errorInvalidPattern => 'Недопустимый шаблон';

  @override
  String get errorIo => 'Не удалось выполнить';

  @override
  String get errorTitle => 'Что-то пошло не так';

  @override
  String sizeBytes(int bytes) {
    return '$bytes Б';
  }

  @override
  String sizeKilobytes(String value) {
    return '$value КБ';
  }

  @override
  String sizeMegabytes(String value) {
    return '$value МБ';
  }

  @override
  String sizeGigabytes(String value) {
    return '$value ГБ';
  }

  @override
  String sizeTerabytes(String value) {
    return '$value ТБ';
  }

  @override
  String relativeToday(String time) {
    return 'Сегодня, $time';
  }

  @override
  String relativeYesterday(String time) {
    return 'Вчера, $time';
  }

  @override
  String get columnName => 'Имя';

  @override
  String get columnExtension => 'Расширение';

  @override
  String get columnSize => 'Размер';

  @override
  String get columnModified => 'Изменён';

  @override
  String get columnCreated => 'Создан';

  @override
  String get columnAdded => 'Добавлен';

  @override
  String get columnAccessed => 'Открыт';

  @override
  String get columnPermissions => 'Права';

  @override
  String get columnOwner => 'Владелец';

  @override
  String get columnGroup => 'Группа';

  @override
  String get collationNatural => 'Естественное';

  @override
  String get collationCaseInsensitive => 'Без учёта регистра';

  @override
  String get collationCaseSensitive => 'С учётом регистра';

  @override
  String get panelParentFolder => 'В родительскую папку';

  @override
  String get panelEmptyFolder => 'Папка пуста';

  @override
  String get panelLoading => 'Чтение…';

  @override
  String get panelFolderSize => 'Папка';

  @override
  String panelItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count объекта',
      many: '$count объектов',
      few: '$count объекта',
      one: '$count объект',
      zero: 'нет объектов',
    );
    return '$_temp0';
  }

  @override
  String panelSelectedSummary(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'выделено $count',
      many: 'выделено $count',
      few: 'выделено $count',
      one: 'выделен $count',
    );
    return '$_temp0, $size';
  }

  @override
  String panelFreeSpace(String free) {
    return 'свободно $free';
  }

  @override
  String panelQuickSearch(String query) {
    return 'Быстрый поиск: $query';
  }

  @override
  String panelSymlinkTo(String target) {
    return '→ $target';
  }

  @override
  String panelSortTooltip(String field) {
    return 'Сортировка: $field';
  }

  @override
  String panelSortSummary(String field, String direction) {
    return 'Сортировка: $field, $direction';
  }

  @override
  String get panelLayoutTooltip => 'Режим просмотра';

  @override
  String get panelMenuTooltip => 'Меню панели';

  @override
  String get panelArchiveBadge => 'Архив';

  @override
  String get panelErrorTitle => 'Не удалось открыть папку';

  @override
  String get panelGoHomeInstead => 'Перейти в домашнюю папку';

  @override
  String get vimModeNormal => 'NORMAL';

  @override
  String get vimModeVisual => 'VISUAL';

  @override
  String get vimModeSearch => 'SEARCH';

  @override
  String get vimModeCommand => 'COMMAND';

  @override
  String vimRegisterCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'вырезано $count',
      many: 'вырезано $count',
      few: 'вырезано $count',
      one: 'вырезан $count',
    );
    return '$_temp0';
  }

  @override
  String vimRegisterYank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'взято $count',
      many: 'взято $count',
      few: 'взято $count',
      one: 'взят $count',
    );
    return '$_temp0';
  }

  @override
  String get vimCommandHint =>
      'cd, mkdir, touch, rename, cp, mv, trash, delete, sort, set hidden, tabnew, tabclose, q, find, marks, help или номер строки';

  @override
  String vimUnknownCommand(String name) {
    return 'Нет такой команды: $name';
  }

  @override
  String vimMarkSet(String letter) {
    return 'Метка $letter поставлена';
  }

  @override
  String vimNoMark(String letter) {
    return 'Нет метки $letter';
  }

  @override
  String get vimMarksTitle => 'Метки';

  @override
  String get vimNoMarks => 'Меток пока нет; поставьте m и букву';

  @override
  String get panelsVimMode => 'Клавиши Vim';

  @override
  String get panelsVimModeHint =>
      'h j k l, счётчики, / для поиска, v для выделения, yy dd p, метки и командная строка :; см. шпаргалку';

  @override
  String get panelHiddenShown => 'Скрытые объекты показаны';

  @override
  String get tabNew => 'Новая вкладка';

  @override
  String get tabClose => 'Закрыть вкладку';

  @override
  String get tabList => 'Все вкладки';

  @override
  String get tabRecentlyClosed => 'Недавно закрытые';

  @override
  String get sortMenuTitle => 'Сортировать по';

  @override
  String get sortAscending => 'По возрастанию';

  @override
  String get sortDescending => 'По убыванию';

  @override
  String get layoutMenuTitle => 'Режим просмотра';

  @override
  String get menuOpen => 'Открыть';

  @override
  String get menuOpenWith => 'Открыть в программе';

  @override
  String get menuOpenWithOther => 'Другая программа…';

  @override
  String get menuShowInFinder => 'Показать в Finder';

  @override
  String get menuShowInExplorer => 'Показать в Проводнике';

  @override
  String get menuShowInFiles => 'Показать в Файлах';

  @override
  String get menuCopyPath => 'Скопировать путь';

  @override
  String get menuCopyName => 'Скопировать имя';

  @override
  String get menuNewFolder => 'Новая папка';

  @override
  String get menuNewFile => 'Новый файл';

  @override
  String get menuSelectAll => 'Выделить всё';

  @override
  String get menuEnterArchive => 'Открыть как папку';

  @override
  String get menuExtractHere => 'Распаковать сюда';

  @override
  String get menuExtractToOpposite => 'Распаковать в другую панель';

  @override
  String copyDialogTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Копировать объекты ($count) в',
      one: 'Копировать «$name» в',
    );
    return '$_temp0';
  }

  @override
  String moveDialogTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Переместить объекты ($count) в',
      one: 'Переместить «$name» в',
    );
    return '$_temp0';
  }

  @override
  String copyAsTitle(String name) {
    return 'Копировать «$name» как';
  }

  @override
  String moveAsTitle(String name) {
    return 'Переместить или переименовать «$name» как';
  }

  @override
  String get destinationLabel => 'Назначение';

  @override
  String get newNameLabel => 'Новое имя';

  @override
  String get optionPreserveAttributes => 'Сохранять права и даты';

  @override
  String get optionVerify => 'Проверять копию';

  @override
  String get conflictsLabel => 'Если объект уже существует';

  @override
  String get conflictAsk => 'Спрашивать';

  @override
  String get conflictOverwrite => 'Заменять';

  @override
  String get conflictOverwriteOlder => 'Заменять более старые';

  @override
  String get conflictSkip => 'Пропускать';

  @override
  String get conflictKeepBoth => 'Оставлять оба';

  @override
  String get createDirectoryTitle => 'Новая папка';

  @override
  String get createDirectoryInOppositeTitle => 'Новая папка в другой панели';

  @override
  String get createDirectoryHint =>
      'Имя или вложенный путь, например Notes/2026';

  @override
  String get createFileTitle => 'Новый файл';

  @override
  String get newFolderDefaultName => 'новая папка';

  @override
  String get newFileDefaultName => 'новый файл.txt';

  @override
  String deleteTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Удалить объекты ($count)?',
      one: 'Удалить «$name»?',
    );
    return '$_temp0';
  }

  @override
  String get deleteMessageTrash => 'Объекты отправятся в Корзину.';

  @override
  String get deleteMessagePermanent => 'Объекты будут удалены безвозвратно.';

  @override
  String get deleteToTrash => 'В Корзину';

  @override
  String get deletePermanently => 'Удалить безвозвратно';

  @override
  String get deleteNothingSelected => 'Нечего удалять';

  @override
  String compressTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Сжать объекты ($count)',
      one: 'Сжать «$name»',
    );
    return '$_temp0';
  }

  @override
  String get archiveNameLabel => 'Имя архива';

  @override
  String get passwordLabel => 'Пароль (AES-256, необязательно)';

  @override
  String get compressHere => 'В этой папке';

  @override
  String get compressToOpposite => 'В другой панели';

  @override
  String get selectMaskTitle => 'Выделить по маске';

  @override
  String get deselectMaskTitle => 'Снять выделение по маске';

  @override
  String get maskLabel => 'Маска или выражение';

  @override
  String get maskHint => '*.jpg; *.png';

  @override
  String get maskRegex => 'Регулярное выражение';

  @override
  String get goToFolderTitle => 'Перейти в папку';

  @override
  String get goToFolderHint => '/путь/к/папке или ~/Documents';

  @override
  String get goToPopupTitle => 'Перейти';

  @override
  String get goToFilterHint => 'Введите текст для фильтра';

  @override
  String get sectionFavorites => 'Избранное';

  @override
  String get sectionVolumes => 'Тома';

  @override
  String get sectionOtherPanel => 'Другая панель';

  @override
  String get sectionHistory => 'История';

  @override
  String get sectionParents => 'Родительские папки';

  @override
  String get quickListEmpty => 'Пока пусто';

  @override
  String volumeFree(String free, String total) {
    return 'свободно $free из $total';
  }

  @override
  String ejectVolume(String name) {
    return 'Извлечь $name';
  }

  @override
  String get favoritesTitle => 'Избранное';

  @override
  String get favoritesAddCurrent => 'Добавить текущую папку';

  @override
  String get favoritesEmpty =>
      'Избранного пока нет. Добавьте текущую папку через меню панели.';

  @override
  String get favoritesRenameTitle => 'Переименовать';

  @override
  String favoriteAdded(String name) {
    return 'Добавлено в избранное: $name';
  }

  @override
  String favoriteRemoved(String name) {
    return 'Убрано из избранного: $name';
  }

  @override
  String attributesTitle(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Атрибуты объектов ($count)',
      one: 'Атрибуты «$name»',
    );
    return '$_temp0';
  }

  @override
  String get permissionsLabel => 'Права';

  @override
  String get permOwner => 'Владелец';

  @override
  String get permGroup => 'Группа';

  @override
  String get permOthers => 'Остальные';

  @override
  String get permRead => 'Чтение';

  @override
  String get permWrite => 'Запись';

  @override
  String get permExecute => 'Выполнение';

  @override
  String get permSetUid => 'Set user ID';

  @override
  String get permSetGid => 'Set group ID';

  @override
  String get permSticky => 'Sticky';

  @override
  String get flagsLabel => 'Флаги';

  @override
  String get flagHidden => 'Скрытый';

  @override
  String get flagLocked => 'Защищён';

  @override
  String get flagAppendOnly => 'Только добавление';

  @override
  String get flagNoDump => 'Без дампа';

  @override
  String get flagArchived => 'Архивный';

  @override
  String get ownerLabel => 'Владелец';

  @override
  String get groupLabel => 'Группа';

  @override
  String get timesLabel => 'Даты';

  @override
  String get modifiedLabel => 'Изменён';

  @override
  String get accessedLabel => 'Открыт';

  @override
  String get createdLabel => 'Создан';

  @override
  String get dateFieldHint => 'гггг-мм-дд чч:мм';

  @override
  String get attributesInvalidDate => 'Неверные дата и время';

  @override
  String get applyRecursively => 'Применить ко всему внутри папок';

  @override
  String attributesUnknownUser(String name) {
    return 'Нет пользователя «$name»';
  }

  @override
  String attributesUnknownGroup(String name) {
    return 'Нет группы «$name»';
  }

  @override
  String attributesFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count объекта не удалось изменить',
      many: '$count объектов не удалось изменить',
      few: '$count объекта не удалось изменить',
      one: '$count объект не удалось изменить',
    );
    return '$_temp0';
  }

  @override
  String batchRenameTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Переименовать $count объекта',
      many: 'Переименовать $count объектов',
      few: 'Переименовать $count объекта',
      one: 'Переименовать $count объект',
    );
    return '$_temp0';
  }

  @override
  String get renamePatternLabel => 'Новое имя';

  @override
  String get renamePatternHint =>
      '[N].[E]  ·  [N] имя, [E] расширение, [C] счётчик, [d] дата';

  @override
  String get renameSearchLabel => 'Найти';

  @override
  String get renameReplaceLabel => 'Заменить на';

  @override
  String get renameRegex => 'Регулярное выражение';

  @override
  String get renameCaseSensitive => 'Учитывать регистр';

  @override
  String get renameOnce => 'Только первое вхождение';

  @override
  String get renameCaseLabel => 'Регистр';

  @override
  String get caseUnchanged => 'Как есть';

  @override
  String get caseLower => 'строчные';

  @override
  String get caseUpper => 'ПРОПИСНЫЕ';

  @override
  String get caseCapitalize => 'Каждое Слово С Прописной';

  @override
  String get partWhole => 'Имя целиком';

  @override
  String get partName => 'Только имя';

  @override
  String get partExtension => 'Только расширение';

  @override
  String get renameCounterLabel => 'Счётчик';

  @override
  String get renameCounterStart => 'Начало';

  @override
  String get renameCounterStep => 'Шаг';

  @override
  String get renameCounterWidth => 'Разрядов';

  @override
  String get renamePreviewOld => 'Текущее имя';

  @override
  String get renamePreviewNew => 'Новое имя';

  @override
  String get renameProblemEmpty => 'Пустое имя';

  @override
  String get renameProblemInvalid => 'Недопустимое имя';

  @override
  String get renameProblemDuplicate => 'Совпадает с другим объектом';

  @override
  String get renameNoChanges => 'Имена не меняются';

  @override
  String renameFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count объекта не удалось переименовать',
      many: '$count объектов не удалось переименовать',
      few: '$count объекта не удалось переименовать',
      one: '$count объект не удалось переименовать',
    );
    return '$_temp0';
  }

  @override
  String get renamePlaceholdersHelp => 'Подстановки';

  @override
  String get renameSearchPartLabel => 'Искать в';

  @override
  String get renameCasePartLabel => 'Применить к';

  @override
  String get renamePlaceholdersText =>
      '[N] имя · [E] расширение · [A] имя целиком · [P] родительская папка · [G] папка уровнем выше · [N2-4] символы со 2-го по 4-й · [N-3,2] два с третьего с конца · [C] счётчик, [C5+2:3] с 5 шагом 2, три разряда · [d] дата · [Y] [M] [D] год, месяц, день · [t] время · [h] [m] [s] · [U] [L] [F] текст далее прописными, строчными, с заглавной · [n] как есть · [[ и ]] скобки';

  @override
  String get symlinkTitle => 'Новая символическая ссылка';

  @override
  String get hardlinkTitle => 'Новая жёсткая ссылка';

  @override
  String get editSymlinkTitle => 'Изменить символическую ссылку';

  @override
  String get linkTargetLabel => 'Указывает на';

  @override
  String get linkNameLabel => 'Имя ссылки';

  @override
  String get linkNotSymlink => 'Объект не является символической ссылкой';

  @override
  String get conflictTitle => 'Уже существует';

  @override
  String get conflictSourceLabel => 'Копируется';

  @override
  String get conflictExistingLabel => 'Существующий';

  @override
  String get conflictFolderLabel => 'Папка';

  @override
  String get questionApplyToAll => 'Применить ко всем';

  @override
  String get questionErrorTitle => 'Не удалось продолжить';

  @override
  String conflictMessage(String name) {
    return '«$name» уже существует в месте назначения.';
  }

  @override
  String questionErrorMessage(String name) {
    return 'Не удалось продолжить с «$name».';
  }

  @override
  String opCopyTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Копирование $count объектов',
      many: 'Копирование $count объектов',
      few: 'Копирование $count объектов',
      one: 'Копирование $count объекта',
    );
    return '$_temp0';
  }

  @override
  String opMoveTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Перемещение $count объектов',
      many: 'Перемещение $count объектов',
      few: 'Перемещение $count объектов',
      one: 'Перемещение $count объекта',
    );
    return '$_temp0';
  }

  @override
  String opDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Удаление $count объектов',
      many: 'Удаление $count объектов',
      few: 'Удаление $count объектов',
      one: 'Удаление $count объекта',
    );
    return '$_temp0';
  }

  @override
  String opTrashTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Перемещение $count объектов в Корзину',
      many: 'Перемещение $count объектов в Корзину',
      few: 'Перемещение $count объектов в Корзину',
      one: 'Перемещение $count объекта в Корзину',
    );
    return '$_temp0';
  }

  @override
  String opDuplicateTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Дублирование $count объектов',
      many: 'Дублирование $count объектов',
      few: 'Дублирование $count объектов',
      one: 'Дублирование $count объекта',
    );
    return '$_temp0';
  }

  @override
  String opCompressTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Сжатие $count объектов',
      many: 'Сжатие $count объектов',
      few: 'Сжатие $count объектов',
      one: 'Сжатие $count объекта',
    );
    return '$_temp0';
  }

  @override
  String opExtractTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Распаковка $count объектов',
      many: 'Распаковка $count объектов',
      few: 'Распаковка $count объектов',
      one: 'Распаковка $count объекта',
    );
    return '$_temp0';
  }

  @override
  String opCalcSizesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Подсчёт размера $count папок',
      many: 'Подсчёт размера $count папок',
      few: 'Подсчёт размера $count папок',
      one: 'Подсчёт размера $count папки',
    );
    return '$_temp0';
  }

  @override
  String get opStateScanning => 'Подсчёт…';

  @override
  String get opStateRunning => 'Выполняется';

  @override
  String get opStatePaused => 'На паузе';

  @override
  String get opStateWaiting => 'Ожидает ответа';

  @override
  String get opStateDone => 'Готово';

  @override
  String get opStateDoneWithErrors => 'Готово с ошибками';

  @override
  String get opStateCancelled => 'Отменено';

  @override
  String get opStateFailed => 'Не выполнено';

  @override
  String opProgressBytes(String done, String total) {
    return '$done из $total';
  }

  @override
  String opProgressItems(int done, int total) {
    return '$done из $total объектов';
  }

  @override
  String opSpeed(String speed) {
    return '$speed/с';
  }

  @override
  String opRemaining(String duration) {
    return 'осталось $duration';
  }

  @override
  String opErrorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ошибки',
      many: '$count ошибок',
      few: '$count ошибки',
      one: '$count ошибка',
    );
    return '$_temp0';
  }

  @override
  String get opErrorsTitle => 'Ошибки';

  @override
  String opTitleTo(String title, String destination) {
    return '$title в $destination';
  }

  @override
  String opFirstError(String name, String message) {
    return '$name: $message';
  }

  @override
  String get operationsTitle => 'Операции';

  @override
  String get operationsEmpty => 'Операций нет';

  @override
  String get operationsClearFinished => 'Убрать завершённые';

  @override
  String noticePathsCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Скопировано $count пути',
      many: 'Скопировано $count путей',
      few: 'Скопировано $count пути',
      one: 'Путь скопирован',
    );
    return '$_temp0';
  }

  @override
  String get noticeNameCopied => 'Имя скопировано';

  @override
  String get noticeNothingSelected => 'Ничего не выделено';

  @override
  String get noticeNotInArchive => 'Внутри архива недоступно';

  @override
  String get noticeClipboardEmpty => 'В буфере обмена нет путей';

  @override
  String noticeEjected(String name) {
    return 'Извлечён том $name';
  }

  @override
  String get noticeNoEditor =>
      'Для этого файла не настроен редактор; см. Настройки → Редакторы';

  @override
  String get noticeNoVolume => 'Здесь нечего извлекать';

  @override
  String get noticeOpenFailed => 'Не удалось открыть объект';

  @override
  String get viewerTitle => 'Просмотр';

  @override
  String get viewerModeText => 'Текст';

  @override
  String get viewerModeHex => 'Hex';

  @override
  String get viewerModePreview => 'Превью';

  @override
  String get viewerGoToTitle => 'Перейти';

  @override
  String get viewerGoToHint => 'Смещение в байтах или проценты, например 50%';

  @override
  String get viewerNoPreview => 'Для этого типа файла нет превью';

  @override
  String get viewerFindHint => 'Найти в файле';

  @override
  String viewerPosition(String offset, String size) {
    return '$offset из $size';
  }

  @override
  String get viewerEncoding => 'UTF-8';

  @override
  String get viewerWrap => 'Переносить строки';

  @override
  String get viewerLoading => 'Чтение…';

  @override
  String viewerWindow(String shown, String size) {
    return 'Показано $shown из $size; остальное — через «Перейти»';
  }

  @override
  String get viewerNoMatch => 'Не найдено';

  @override
  String get viewerEmptyFile => 'Файл пуст';

  @override
  String get viewerBinaryHint => 'Двоичные данные: переключитесь в Hex';

  @override
  String viewerLine(int line) {
    return 'Строка $line';
  }

  @override
  String viewerMatches(int current, int total) {
    return '$current из $total';
  }

  @override
  String get viewerLoadNext => 'Следующая часть';

  @override
  String get viewerLoadPrevious => 'Предыдущая часть';

  @override
  String get findTitle => 'Поиск файлов';

  @override
  String get findIn => 'В папке';

  @override
  String get findName => 'Имя';

  @override
  String get findNameHint => '*.txt; отчёт*';

  @override
  String get findRegex => 'Регулярное выражение';

  @override
  String get findContent => 'Содержит текст';

  @override
  String get findCaseSensitive => 'Учитывать регистр';

  @override
  String get findWholePhrase => 'Фраза целиком';

  @override
  String get findNotContaining => 'Не содержит';

  @override
  String get findSize => 'Размер';

  @override
  String get findSizeAny => 'Любой';

  @override
  String get findSizeLess => 'Меньше';

  @override
  String get findSizeEqual => 'Равен';

  @override
  String get findSizeGreater => 'Больше';

  @override
  String get findIncludeHidden => 'Искать среди скрытых';

  @override
  String get findStart => 'Найти';

  @override
  String get findStop => 'Остановить';

  @override
  String findResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Найдено $count объекта',
      many: 'Найдено $count объектов',
      few: 'Найдено $count объекта',
      one: 'Найден $count объект',
      zero: 'Ничего не найдено',
    );
    return '$_temp0';
  }

  @override
  String findScanning(String path) {
    return 'Просмотр $path';
  }

  @override
  String get findGoTo => 'Перейти';

  @override
  String get findView => 'Просмотр';

  @override
  String get findNoResults => 'Совпадений нет';

  @override
  String findError(String message) {
    return 'Поиск не запустился: $message';
  }

  @override
  String get findColumnFolder => 'Папка';

  @override
  String get findUnitBytes => 'Б';

  @override
  String get findUnitKilobytes => 'КБ';

  @override
  String get findUnitMegabytes => 'МБ';

  @override
  String get findUnitGigabytes => 'ГБ';

  @override
  String findResultsCapped(int count) {
    return 'Показаны первые $count; уточните условия, чтобы увидеть остальное';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsGeneral => 'Основные';

  @override
  String get settingsPanels => 'Панели';

  @override
  String get settingsViewer => 'Просмотр';

  @override
  String get settingsHotkeys => 'Клавиши';

  @override
  String get settingsEditors => 'Редакторы';

  @override
  String get settingsTools => 'Инструменты';

  @override
  String get settingsAbout => 'О программе';

  @override
  String get settingsSearchHint => 'Поиск по настройкам';

  @override
  String get themeLabel => 'Оформление';

  @override
  String get themeSystem => 'Как в системе';

  @override
  String get themeLight => 'Светлое';

  @override
  String get themeDark => 'Тёмное';

  @override
  String get languageLabel => 'Язык';

  @override
  String get languageSystem => 'Как в системе';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Русский';

  @override
  String get textSizeLabel => 'Размер текста';

  @override
  String textSizePercent(int percent) {
    return '$percent%';
  }

  @override
  String get confirmationsLabel => 'Подтверждения';

  @override
  String get confirmTrashLabel => 'Спрашивать перед отправкой в Корзину';

  @override
  String get confirmDeleteLabel => 'Спрашивать перед безвозвратным удалением';

  @override
  String get generalKeyHintsLabel => 'Подсказки клавиш под панелями';

  @override
  String get generalKeyHintsNote =>
      'Одна строка с клавишами для того, что под курсором или выделено';

  @override
  String get hintsHide => 'Скрыть подсказки';

  @override
  String get hintsHidden =>
      'Подсказки выключены; включить снова: Настройки, Основные';

  @override
  String get hintBack => 'Назад';

  @override
  String get hintKeepMatches => 'Оставить совпадения';

  @override
  String get copyDefaultsLabel => 'Копирование';

  @override
  String get panelsShowHidden => 'Показывать скрытые объекты';

  @override
  String get panelsParentEntry => 'Показывать строку «..»';

  @override
  String get panelsFoldersFirst => 'Папки перед файлами';

  @override
  String get panelsExtensionlessFolders =>
      'При сортировке у папок нет расширения';

  @override
  String get panelsCollation => 'Сравнение имён';

  @override
  String get panelsTabBarAlways => 'Всегда показывать панель вкладок';

  @override
  String get quickSearchTitle => 'Быстрый поиск';

  @override
  String get quickSearchWhere => 'Где искать';

  @override
  String get quickSearchFuzzy => 'Нечётко';

  @override
  String get quickSearchAnywhere => 'В любом месте';

  @override
  String get quickSearchBeginning => 'В начале';

  @override
  String get quickSearchEnding => 'В конце';

  @override
  String get quickSearchBeginningOrEnding => 'В начале или в конце';

  @override
  String get quickSearchModifier => 'Модификатор';

  @override
  String get modifierNone => 'Без модификатора';

  @override
  String get modifierAlt => 'Option';

  @override
  String get modifierControlAlt => 'Control + Option';

  @override
  String get modifierShiftAlt => 'Shift + Option';

  @override
  String get modifierDisabled => 'Выключен';

  @override
  String get quickSearchOnlyMatching => 'Показывать только совпадения';

  @override
  String get layoutsTitle => 'Режимы просмотра';

  @override
  String get layoutName => 'Название';

  @override
  String get layoutMode => 'Режим';

  @override
  String get modeBrief => 'Краткий';

  @override
  String get modeList => 'Список';

  @override
  String get briefColumnsLabel => 'Колонки';

  @override
  String get briefColumnsFixed => 'Три равные колонки';

  @override
  String get briefColumnsDynamic => 'По ширине имён';

  @override
  String get columnsLabel => 'Столбцы';

  @override
  String get layoutsReset => 'Вернуть режимы по умолчанию';

  @override
  String get viewerWrapLabel => 'Переносить длинные строки';

  @override
  String get viewerFontSizeLabel => 'Размер шрифта';

  @override
  String get hotkeysReset => 'Вернуть по умолчанию';

  @override
  String get hotkeysResetOne => 'Вернуть по умолчанию';

  @override
  String get hotkeysRecord => 'Нажмите новую клавишу…';

  @override
  String hotkeysRecordTitle(String command) {
    return 'Клавиша для «$command»';
  }

  @override
  String hotkeysConflict(String command) {
    return 'Уже занято: «$command»';
  }

  @override
  String get hotkeysReassign => 'Переназначить';

  @override
  String get hotkeysChanged => 'Изменено относительно стандартного';

  @override
  String lengthPoints(int value) {
    return '$value пт';
  }

  @override
  String lengthPixels(int value) {
    return '$value px';
  }

  @override
  String get hotkeysUnbound => 'Нет';

  @override
  String get hotkeysSearchHint => 'Поиск команд';

  @override
  String get hotkeysChange => 'Изменить';

  @override
  String get hotkeysClear => 'Убрать клавишу';

  @override
  String get editorsIntro =>
      'F4 открывает файл под курсором первым редактором, маска которого подходит к имени.';

  @override
  String get editorName => 'Название';

  @override
  String get editorPath => 'Программа';

  @override
  String get editorMask => 'Маски файлов';

  @override
  String get editorInTerminal => 'Запускать в терминале';

  @override
  String get editorsEmpty => 'Редакторов пока нет';

  @override
  String get editorsAdd => 'Добавить редактор';

  @override
  String get editorAddTitle => 'Новый редактор';

  @override
  String get editorEditTitle => 'Редактор';

  @override
  String get toolsIntro =>
      'Инструменты запускают программу с объектами панелей в аргументах: %p путь под курсором, %f его имя, %r папка панели, %P все выделенные пути, %-… то же для другой панели.';

  @override
  String get toolTitle => 'Название';

  @override
  String get toolPath => 'Программа';

  @override
  String get toolParameters => 'Аргументы';

  @override
  String get toolInTerminal => 'Запускать в терминале';

  @override
  String get toolsEmpty => 'Инструментов пока нет';

  @override
  String get toolsAdd => 'Добавить инструмент';

  @override
  String get toolAddTitle => 'Новый инструмент';

  @override
  String get toolEditTitle => 'Инструмент';

  @override
  String get toolRun => 'Запустить';

  @override
  String get toolAskValueTitle => 'Значение для инструмента';

  @override
  String get choosePath => 'Выбрать…';

  @override
  String get cheatSheetTitle => 'Клавиатурные сокращения';

  @override
  String get cheatSheetHint =>
      'Все клавиши окна; изменить их можно в Настройки → Клавиши.';

  @override
  String get scopeGlobal => 'Везде';

  @override
  String get scopePanel => 'Файловая панель';

  @override
  String get scopeViewer => 'Просмотр';

  @override
  String get scopeLists => 'Списки';

  @override
  String get scopeDialogs => 'Диалоги';

  @override
  String get windowClose => 'Закрыть';

  @override
  String get windowMinimize => 'Свернуть';

  @override
  String get windowMaximize => 'Развернуть';

  @override
  String get hintModeHint => 'Введите метку, чтобы нажать; Esc — выйти';

  @override
  String get splitterTitle => 'Размеры панелей';

  @override
  String get splitterHintArrows => 'Двигать границу';

  @override
  String get splitterHintZero => 'Поровну';

  @override
  String get splitterHintEnter => 'Оставить';

  @override
  String get splitterHintEscape => 'Вернуть';

  @override
  String get singlePaneTooltip => 'Одна панель';

  @override
  String get dualPaneTooltip => 'Две панели';

  @override
  String get panelLeft => 'Левая панель';

  @override
  String get panelRight => 'Правая панель';

  @override
  String get cmdNewFolder => 'Новая папка';

  @override
  String get cmdNewFolderWithSelection => 'Новая папка с выделенным';

  @override
  String get cmdNewFile => 'Новый файл';

  @override
  String get cmdNewTab => 'Новая вкладка';

  @override
  String get cmdCloseTab => 'Закрыть вкладку';

  @override
  String get cmdCloseOtherTabs => 'Закрыть другие вкладки';

  @override
  String get cmdReopenClosedTab => 'Открыть закрытую вкладку';

  @override
  String get cmdNextTab => 'Следующая вкладка';

  @override
  String get cmdPreviousTab => 'Предыдущая вкладка';

  @override
  String get cmdToggleTabBar => 'Показать панель вкладок';

  @override
  String get cmdOpenItem => 'Открыть';

  @override
  String get cmdRevealInOppositePanel => 'Показать в другой панели';

  @override
  String get cmdRevealInOppositeTab => 'Показать во вкладке другой панели';

  @override
  String get cmdCalcFolderSizes => 'Подсчитать размеры папок';

  @override
  String get cmdCalcAllFolderSizes => 'Подсчитать размеры всех папок';

  @override
  String get cmdDuplicate => 'Дублировать';

  @override
  String get cmdAddToFavorites => 'Добавить в избранное';

  @override
  String get cmdManageFavorites => 'Управление избранным…';

  @override
  String get cmdFindFiles => 'Найти файлы…';

  @override
  String get cmdCopyPaths => 'Копировать';

  @override
  String get cmdPasteItems => 'Вставить';

  @override
  String get cmdMoveItemsHere => 'Переместить объекты сюда';

  @override
  String get cmdSelectAll => 'Выделить всё';

  @override
  String get cmdDeselectAll => 'Снять выделение';

  @override
  String get cmdInvertSelection => 'Обратить выделение';

  @override
  String get cmdSelectWithMask => 'Выделить по маске…';

  @override
  String get cmdDeselectWithMask => 'Снять выделение по маске…';

  @override
  String get cmdSelectWithExtension => 'Выделить по расширению';

  @override
  String get cmdDeselectWithExtension => 'Снять выделение по расширению';

  @override
  String get cmdToggleSinglePane => 'Одна или две панели';

  @override
  String get cmdSwapPanels => 'Поменять панели местами';

  @override
  String get cmdSyncPanels => 'Синхронизировать панели';

  @override
  String cmdViewMode(int number) {
    return 'Режим просмотра $number';
  }

  @override
  String get cmdSortByName => 'Сортировать по имени';

  @override
  String get cmdSortByExtension => 'Сортировать по расширению';

  @override
  String get cmdSortByModified => 'Сортировать по дате изменения';

  @override
  String get cmdSortBySize => 'Сортировать по размеру';

  @override
  String get cmdSortByCreated => 'Сортировать по дате создания';

  @override
  String get cmdSortByAdded => 'Сортировать по дате добавления';

  @override
  String get cmdSortByAccessed => 'Сортировать по дате открытия';

  @override
  String get cmdToggleFoldersFirst => 'Папки отдельно от файлов';

  @override
  String get cmdToggleExtensionlessFolders => 'Папки без расширения';

  @override
  String get cmdCollationNatural => 'Естественное сравнение';

  @override
  String get cmdCollationCaseInsensitive => 'Сравнение без учёта регистра';

  @override
  String get cmdCollationCaseSensitive => 'Сравнение с учётом регистра';

  @override
  String get cmdToggleHiddenFiles => 'Показывать скрытые объекты';

  @override
  String get cmdPanelsMoveLeft => 'Сдвинуть границу влево';

  @override
  String get cmdPanelsMoveRight => 'Сдвинуть границу вправо';

  @override
  String get cmdResizePanels => 'Размеры панелей с клавиатуры';

  @override
  String get cmdRefresh => 'Обновить';

  @override
  String get cmdToggleOperations => 'Показать операции';

  @override
  String get cmdGoToLeftPanel => 'Перейти… (левая панель)';

  @override
  String get cmdGoToRightPanel => 'Перейти… (правая панель)';

  @override
  String get cmdGoBack => 'Назад';

  @override
  String get cmdGoForward => 'Вперёд';

  @override
  String get cmdGoEnclosingFolder => 'Родительская папка';

  @override
  String get cmdGoInto => 'Войти';

  @override
  String get cmdFollowSymlink => 'Перейти по ссылке';

  @override
  String get cmdGoDocuments => 'Документы';

  @override
  String get cmdGoDesktop => 'Рабочий стол';

  @override
  String get cmdGoDownloads => 'Загрузки';

  @override
  String get cmdGoHome => 'Домашняя папка';

  @override
  String get cmdGoLibrary => 'Библиотека';

  @override
  String get cmdGoApplications => 'Программы';

  @override
  String get cmdGoUtilities => 'Утилиты';

  @override
  String get cmdGoRoot => 'Корень';

  @override
  String get cmdQuickListParents => 'Родительские папки';

  @override
  String get cmdQuickListHistory => 'История';

  @override
  String get cmdQuickListFavorites => 'Избранное';

  @override
  String get cmdQuickListVolumes => 'Тома';

  @override
  String get cmdGoToFolder => 'Перейти в папку…';

  @override
  String get cmdFileAttributes => 'Атрибуты файла…';

  @override
  String get cmdCopyItemName => 'Скопировать имя';

  @override
  String get cmdCopyItemPath => 'Скопировать путь';

  @override
  String get cmdCopyItemDirectory => 'Скопировать папку объекта';

  @override
  String get cmdPreview => 'Просмотр';

  @override
  String get cmdInternalViewer => 'Встроенный просмотрщик';

  @override
  String get cmdExternalEditor => 'Внешний редактор';

  @override
  String get cmdEjectVolume => 'Извлечь том';

  @override
  String get cmdBatchRename => 'Пакетное переименование…';

  @override
  String get cmdCopyTo => 'Копировать в…';

  @override
  String get cmdCopyAs => 'Копировать как…';

  @override
  String get cmdMoveTo => 'Переместить в…';

  @override
  String get cmdMoveAs => 'Переместить как…';

  @override
  String get cmdRenameInPlace => 'Переименовать на месте';

  @override
  String get cmdCreateDirectory => 'Создать папку…';

  @override
  String get cmdCreateDirectoryInOppositePanel =>
      'Создать папку в другой панели…';

  @override
  String get cmdMoveToTrash => 'В Корзину';

  @override
  String get cmdDeleteItems => 'Удалить…';

  @override
  String get cmdDeletePermanently => 'Удалить безвозвратно…';

  @override
  String get cmdCompress => 'Сжать…';

  @override
  String get cmdCompressTo => 'Сжать в…';

  @override
  String get cmdCreateSymlink => 'Создать символическую ссылку…';

  @override
  String get cmdCreateHardlink => 'Создать жёсткую ссылку…';

  @override
  String get cmdEditSymlink => 'Изменить символическую ссылку…';

  @override
  String get cmdRevealInFileManager => 'Показать в файловом менеджере';

  @override
  String get cmdOpenWith => 'Открыть в программе…';

  @override
  String get cmdFocusLeftPanel => 'Фокус на левую панель';

  @override
  String get cmdFocusRightPanel => 'Фокус на правую панель';

  @override
  String get cmdOpenSettings => 'Настройки…';

  @override
  String get cmdHintMode => 'Подсказки для кликов';

  @override
  String get cmdCheatSheet => 'Клавиатурные сокращения';

  @override
  String get cmdContextMenu => 'Контекстное меню';

  @override
  String get cmdMoveUp => 'Вверх';

  @override
  String get cmdMoveDown => 'Вниз';

  @override
  String get cmdMoveLeft => 'Влево';

  @override
  String get cmdMoveRight => 'Вправо';

  @override
  String get cmdMoveFirst => 'К первому объекту';

  @override
  String get cmdMoveLast => 'К последнему объекту';

  @override
  String get cmdScrollFirst => 'Прокрутить к первому объекту';

  @override
  String get cmdScrollLast => 'Прокрутить к последнему объекту';

  @override
  String get cmdMovePageUp => 'На страницу вверх';

  @override
  String get cmdMovePageDown => 'На страницу вниз';

  @override
  String get cmdScrollPageUp => 'Прокрутить на страницу вверх';

  @override
  String get cmdScrollPageDown => 'Прокрутить на страницу вниз';

  @override
  String get cmdSelectMoveUp => 'Выделить и вверх';

  @override
  String get cmdSelectMoveDown => 'Выделить и вниз';

  @override
  String get cmdSelectMoveLeft => 'Выделить и влево';

  @override
  String get cmdSelectMoveRight => 'Выделить и вправо';

  @override
  String get cmdSelectMoveFirst => 'Выделить до первого объекта';

  @override
  String get cmdSelectMoveLast => 'Выделить до последнего объекта';

  @override
  String get cmdSelectMovePageUp => 'Выделить на страницу вверх';

  @override
  String get cmdSelectMovePageDown => 'Выделить на страницу вниз';

  @override
  String get cmdToggleSelection => 'Переключить выделение';

  @override
  String get cmdToggleSelectionMoveDown => 'Переключить выделение и вниз';

  @override
  String get cmdEnterItem => 'Войти';

  @override
  String get cmdGoParent => 'В родительскую папку';

  @override
  String get cmdSwitchPanel => 'Сменить активную панель';

  @override
  String get cmdShowPreview => 'Показать превью';

  @override
  String get cmdClearQuickSearch => 'Очистить быстрый поиск';

  @override
  String cmdShowTab(int number) {
    return 'Показать вкладку $number';
  }

  @override
  String get cmdViewerText => 'Текст';

  @override
  String get cmdViewerHex => 'Hex';

  @override
  String get cmdViewerPreview => 'Превью';

  @override
  String get cmdViewerGoTo => 'Перейти к смещению…';

  @override
  String get cmdViewerFind => 'Найти…';

  @override
  String get cmdViewerFindNext => 'Найти далее';

  @override
  String get cmdViewerFindPrevious => 'Найти ранее';

  @override
  String get cmdViewerToggleWrap => 'Переносить строки';

  @override
  String get cmdRenameItem => 'Переименовать';

  @override
  String get cmdDeleteItem => 'Удалить';

  @override
  String get cmdFilterList => 'Фильтр';

  @override
  String get cmdMoveItemUp => 'Выше';

  @override
  String get cmdVimVisual => 'Визуальное выделение';

  @override
  String get cmdVimSearch => 'Поиск в панели';

  @override
  String get cmdVimSearchNext => 'Следующее совпадение';

  @override
  String get cmdVimSearchPrevious => 'Предыдущее совпадение';

  @override
  String get cmdVimCommandLine => 'Командная строка';

  @override
  String get cmdVimCut => 'Вырезать (взять для перемещения)';

  @override
  String get cmdVimYank => 'Yank (взять для копирования)';

  @override
  String get cmdVimPaste => 'Вставить сюда';

  @override
  String get cmdVimCancelRegister => 'Отпустить взятые объекты';

  @override
  String get cmdVimFindChar => 'Перейти к имени по первой букве';

  @override
  String get cmdVimFindCharBack => 'Перейти назад к имени по первой букве';

  @override
  String get cmdVimRepeatFind => 'Повторить переход';

  @override
  String get cmdVimRepeatFindBack => 'Повторить переход назад';

  @override
  String get cmdVimSetMark => 'Поставить метку';

  @override
  String get cmdVimGoMark => 'Перейти к метке';

  @override
  String get cmdVimScreenTop => 'Верх экрана';

  @override
  String get cmdVimScreenMiddle => 'Середина экрана';

  @override
  String get cmdVimScreenBottom => 'Низ экрана';

  @override
  String get cmdVimScrollCenter => 'Прокрутить курсор в середину';

  @override
  String get cmdVimScrollTop => 'Прокрутить курсор наверх';

  @override
  String get cmdVimScrollBottom => 'Прокрутить курсор вниз';

  @override
  String get cmdVimHalfPageDown => 'На полстраницы вниз';

  @override
  String get cmdVimHalfPageUp => 'На полстраницы вверх';

  @override
  String get cmdVimColumnNext => 'Следующая колонка';

  @override
  String get cmdVimColumnPrevious => 'Предыдущая колонка';

  @override
  String get cmdVimRenameAppend => 'Переименовать с конца имени';

  @override
  String get cmdVimRenamePrepend => 'Переименовать с начала имени';

  @override
  String get cmdVimSortReverse => 'Обратить порядок сортировки';

  @override
  String get cmdVimReselect => 'Выделить прошлое выделение снова';

  @override
  String get cmdMoveItemDown => 'Ниже';

  @override
  String get cmdConfirm => 'Подтвердить';

  @override
  String get cmdDismiss => 'Закрыть';

  @override
  String get cmdCommandPalette => 'Палитра команд';

  @override
  String get cmdJumpToFolder => 'Перейти к частой папке';

  @override
  String get cmdAddToShelf => 'Положить на полку';

  @override
  String get cmdToggleShelf => 'Показать или скрыть полку';

  @override
  String get cmdRenameInEditor => 'Переименовать в редакторе';

  @override
  String get paletteHint => 'Введите команду';

  @override
  String get paletteNoResults => 'Нет подходящих команд';

  @override
  String get paletteRecent => 'Недавние';

  @override
  String get paletteKeySelect => 'выбрать';

  @override
  String get paletteKeyRun => 'выполнить';

  @override
  String get paletteKeyClose => 'закрыть';

  @override
  String get paletteSectionFile => 'Файл';

  @override
  String get paletteSectionEdit => 'Правка';

  @override
  String get paletteSectionView => 'Вид';

  @override
  String get paletteSectionGo => 'Переход';

  @override
  String get paletteSectionCommand => 'Команды';

  @override
  String get paletteSectionWindow => 'Окно';

  @override
  String get paletteSectionPanel => 'Файловая панель';

  @override
  String get paletteSectionVim => 'Vim';

  @override
  String get paletteSectionViewer => 'Просмотр';

  @override
  String get paletteSectionLists => 'Списки';

  @override
  String get paletteSectionDialogs => 'Диалоги';

  @override
  String get jumpTitle => 'Переход к частой папке';

  @override
  String get jumpHint => 'Введите части пути к папке';

  @override
  String get jumpEmpty =>
      'Здесь появятся папки, которые вы открываете, — частые первыми';

  @override
  String get jumpNoResults => 'Среди посещённых папок подходящих нет';

  @override
  String get jumpKeyOpen => 'открыть';

  @override
  String get jumpKeyNewTab => 'в новой вкладке';

  @override
  String get jumpKeyOtherPanel => 'в другой панели';

  @override
  String jumpGone(String path) {
    return 'Папки $path больше нет — она убрана из списка';
  }

  @override
  String jumpNoMatch(String query) {
    return 'Среди посещённых папок нет подходящей для «$query»';
  }

  @override
  String get shelfTitle => 'Полка';

  @override
  String shelfNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count на полке',
      many: '$count на полке',
      few: '$count на полке',
      one: '$count на полке',
    );
    return '$_temp0';
  }

  @override
  String shelfAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'На полку положено $count объекта',
      many: 'На полку положено $count объектов',
      few: 'На полку положено $count объекта',
      one: 'На полку положен $count объект',
    );
    return '$_temp0';
  }

  @override
  String shelfEmpty(String key) {
    return 'Соберите файлы из любых папок клавишами $key, а потом скопируйте или переместите их сюда вместе';
  }

  @override
  String get shelfClear => 'Очистить';

  @override
  String get shelfCopyHere => 'Копировать сюда';

  @override
  String get shelfMoveHere => 'Переместить сюда';

  @override
  String shelfInto(String folder) {
    return 'В папку $folder';
  }

  @override
  String get shelfRemove => 'Убрать с полки';

  @override
  String get shelfMissing => 'больше нет на месте';

  @override
  String shelfMissingTooltip(String path) {
    return '$path больше нет на диске';
  }

  @override
  String get shelfCutTooltip => 'При вставке переместится, а не скопируется';

  @override
  String get shelfAlreadyHere => 'Объекты с полки уже в этой папке';

  @override
  String get shelfNothingToPut =>
      'Ни одного объекта с полки больше нет на диске';

  @override
  String get shelfHintReveal => 'Показать в панели';

  @override
  String get shelfHintRemove => 'Убрать';

  @override
  String namesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Переименовать $count объекта',
      many: 'Переименовать $count объектов',
      few: 'Переименовать $count объекта',
      one: 'Переименовать $count объект',
    );
    return '$_temp0';
  }

  @override
  String namesHint(String apply, String newline) {
    return 'По имени на строку, в показанном порядке. $apply переименовывает, $newline начинает новую строку.';
  }

  @override
  String namesToRename(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count к переименованию',
      many: '$count к переименованию',
      few: '$count к переименованию',
      one: '$count к переименованию',
      zero: 'Пока ничего не меняется',
    );
    return '$_temp0';
  }

  @override
  String namesErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ошибки',
      many: '$count ошибок',
      few: '$count ошибки',
      one: '$count ошибка',
    );
    return '$_temp0';
  }

  @override
  String namesLineCount(int names, int lines) {
    return 'Для имён нужно строк: $names, а их $lines';
  }

  @override
  String namesProblemEmpty(int line) {
    return 'Строка $line: пустое имя';
  }

  @override
  String namesProblemSeparator(int line) {
    return 'Строка $line: в имени не может быть «/»';
  }

  @override
  String namesProblemInvalid(int line) {
    return 'Строка $line: такого имени у файла быть не может';
  }

  @override
  String namesProblemDuplicate(int line, int other) {
    return 'Строка $line: то же имя, что в строке $other';
  }

  @override
  String namesProblemExists(int line, String name) {
    return 'Строка $line: «$name» уже есть в этой папке';
  }

  @override
  String namesProblemExtra(int line) {
    return 'Строка $line: для этой строки нет объекта';
  }

  @override
  String namesProblemMissing(int line) {
    return 'Строка $line: для этого объекта нет строки';
  }

  @override
  String get namesShortEmpty => 'пусто';

  @override
  String get namesShortSeparator => 'есть /';

  @override
  String get namesShortInvalid => 'не имя';

  @override
  String get namesShortDuplicate => 'повтор';

  @override
  String get namesShortExists => 'занято';

  @override
  String get namesShortExtra => 'лишняя';

  @override
  String get namesShortMissing => 'нет строки';

  @override
  String get namesDiscardTitle => 'Отменить новые имена?';

  @override
  String get namesDiscardMessage =>
      'Введённые имена пропадут, ничего не переименуется.';

  @override
  String get namesDiscard => 'Не сохранять';

  @override
  String get namesKeepEditing => 'Продолжить';

  @override
  String get cmdQuickLook => 'Быстрый просмотр';

  @override
  String get cmdShare => 'Поделиться…';

  @override
  String get nativeUnavailable => 'Недоступно в этой системе';

  @override
  String get quickLookNothing => 'Здесь нечего смотреть';

  @override
  String quickLookTooLarge(String name) {
    return '«$name» слишком велик для просмотра из архива';
  }

  @override
  String get dropIntoItself => 'Папку нельзя положить в неё саму';

  @override
  String get dropNoFiles => 'Сюда можно перетащить только файлы и папки';

  @override
  String get cmdToggleTerminal => 'Терминал на всё окно';

  @override
  String get cmdShowTerminal => 'Показать терминал';

  @override
  String get cmdHideTerminal => 'Скрыть терминал';

  @override
  String get cmdTogglePanelsOverTerminal => 'Скрыть или показать панели';

  @override
  String get cmdTerminalCopy => 'Копировать';

  @override
  String get cmdTerminalPaste => 'Вставить';

  @override
  String get cmdTerminalSelectAll => 'Выделить всё';

  @override
  String get cmdTerminalClear => 'Очистить';

  @override
  String get cmdTerminalScrollPageUp => 'Прокрутить на страницу вверх';

  @override
  String get cmdTerminalScrollPageDown => 'Прокрутить на страницу вниз';

  @override
  String get scopeTerminal => 'Терминал';

  @override
  String get settingsTerminal => 'Терминал';

  @override
  String get terminalShellLabel => 'Оболочка';

  @override
  String terminalShellDefault(String shell) {
    return 'По умолчанию: $shell';
  }

  @override
  String get terminalShellNote =>
      'Путь или имя из PATH, запускается как оболочка входа; действует со следующей запущенной оболочки';

  @override
  String get terminalFontSizeLabel => 'Размер шрифта';

  @override
  String get terminalScrollbackLabel => 'Строк для прокрутки назад';

  @override
  String terminalLineCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString строки',
      many: '$countString строк',
      few: '$countString строки',
      one: '$countString строка',
    );
    return '$_temp0';
  }

  @override
  String get terminalHeightTitle => 'Высота терминала';

  @override
  String get terminalHeightHintArrows => 'По строке';

  @override
  String get terminalHeightHintZero => 'Высота по умолчанию';

  @override
  String get terminalExited => 'Оболочка завершилась';

  @override
  String terminalExitedWithCode(int code) {
    return 'Оболочка завершилась с кодом $code';
  }

  @override
  String get terminalStartFailed => 'Не удалось запустить оболочку';

  @override
  String get terminalRestart => 'Новая оболочка';

  @override
  String terminalRestartHint(String key) {
    return '$key — запустить новую оболочку';
  }

  @override
  String get terminalTitle => 'Терминал';

  @override
  String get terminalBusy =>
      'В терминале работает программа или набрана строка';

  @override
  String get terminalScrollbackNote => 'Столько хранит новая оболочка';

  @override
  String get paletteSectionTerminal => 'Терминал';

  @override
  String get cmdCompareFolders => 'Сравнить папки';

  @override
  String get cmdSynchronizeFolders => 'Синхронизировать папки…';

  @override
  String get cmdUndo => 'Отменить';

  @override
  String get cmdRedo => 'Повторить';

  @override
  String get cmdChecksums => 'Контрольные суммы…';

  @override
  String get cmdFindDuplicates => 'Найти дубликаты…';

  @override
  String opSynchronizeTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Синхронизация $count объекта',
      many: 'Синхронизация $count объектов',
      few: 'Синхронизация $count объектов',
      one: 'Синхронизация $count объекта',
    );
    return '$_temp0';
  }

  @override
  String opCompareContentsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Сравнение $count пары файлов',
      many: 'Сравнение $count пар файлов',
      few: 'Сравнение $count пар файлов',
      one: 'Сравнение $count пары файлов',
    );
    return '$_temp0';
  }

  @override
  String opUndoTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Отмена $count изменения',
      many: 'Отмена $count изменений',
      few: 'Отмена $count изменений',
      one: 'Отмена $count изменения',
    );
    return '$_temp0';
  }

  @override
  String opRedoTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Повтор $count изменения',
      many: 'Повтор $count изменений',
      few: 'Повтор $count изменений',
      one: 'Повтор $count изменения',
    );
    return '$_temp0';
  }

  @override
  String compareSelected(String left, String right) {
    return 'Выделено: слева $left, справа $right';
  }

  @override
  String get compareSame => 'В папках одни и те же файлы';

  @override
  String get compareNeedsFolders => 'В обеих панелях должны быть открыты папки';

  @override
  String get compareSameFolder => 'Обе панели показывают одну и ту же папку';

  @override
  String compareContentsStarted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Сравнение содержимого $count пары файлов…',
      many: 'Сравнение содержимого $count пар файлов…',
      few: 'Сравнение содержимого $count пар файлов…',
      one: 'Сравнение содержимого $count пары файлов…',
    );
    return '$_temp0';
  }

  @override
  String get compareContentsNotHere =>
      'Содержимое сравнивается только для папок на диске; сравнено по размеру и дате';

  @override
  String get compareGroupLabel => 'Сравнение папок';

  @override
  String get compareContentsSetting =>
      'Сравнивать содержимое файлов одного размера';

  @override
  String journalWhatOne(String name) {
    return '«$name»';
  }

  @override
  String journalWhatMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count объекта',
      many: '$count объектов',
      few: '$count объектов',
      one: '$count объекта',
    );
    return '$_temp0';
  }

  @override
  String journalStepCopy(String what) {
    return 'копирование $what';
  }

  @override
  String journalStepMove(String what) {
    return 'перемещение $what';
  }

  @override
  String journalStepTrash(String what) {
    return 'перемещение в Корзину $what';
  }

  @override
  String journalStepRename(String what) {
    return 'переименование $what';
  }

  @override
  String journalStepCreateFolder(String what) {
    return 'новая папка $what';
  }

  @override
  String journalStepCreateFile(String what) {
    return 'новый файл $what';
  }

  @override
  String journalStepCreateLink(String what) {
    return 'новая ссылка $what';
  }

  @override
  String journalStepDuplicate(String what) {
    return 'дублирование $what';
  }

  @override
  String journalStepCompress(String what) {
    return 'сжатие $what';
  }

  @override
  String journalStepExtract(String what) {
    return 'извлечение $what';
  }

  @override
  String journalStepSynchronize(String what) {
    return 'синхронизация $what';
  }

  @override
  String undoMenu(String step) {
    return 'Отменить: $step';
  }

  @override
  String redoMenu(String step) {
    return 'Повторить: $step';
  }

  @override
  String undoCardTitle(String step) {
    return 'Отмена: $step';
  }

  @override
  String redoCardTitle(String step) {
    return 'Повтор: $step';
  }

  @override
  String get undoNothing => 'Нечего отменять';

  @override
  String get redoNothing => 'Нечего повторять';

  @override
  String get undoMoved =>
      'Файлы успели измениться другим действием; попробуйте ещё раз';

  @override
  String undoDialogTitle(String step) {
    return 'Отменить: $step?';
  }

  @override
  String redoDialogTitle(String step) {
    return 'Повторить: $step?';
  }

  @override
  String undoPartly(int doable, int total) {
    return 'Можно отменить $doable из $total изменений. Нельзя отменить:';
  }

  @override
  String redoPartly(int doable, int total) {
    return 'Можно повторить $doable из $total изменений. Нельзя повторить:';
  }

  @override
  String get undoNone => 'Ни одно из изменений уже нельзя отменить:';

  @override
  String get redoNone => 'Ни одно из изменений уже нельзя повторить:';

  @override
  String get undoWarnings => 'Отменить можно, но учтите:';

  @override
  String get redoWarnings => 'Повторить можно, но учтите:';

  @override
  String get undoIssueMissing => 'Больше нет на месте';

  @override
  String get undoIssueOccupied => 'Место уже занято';

  @override
  String get undoIssueChanged =>
      'Изменился с тех пор; всё равно отправится в Корзину';

  @override
  String get undoIssueLost =>
      'Был заменён: прежнее содержимое утеряно, останется как есть';

  @override
  String get undoIssueNotInTrash => 'Больше нет в Корзине';

  @override
  String get undoIssueUnsupported => 'Здесь нельзя вернуть объекты из Корзины';

  @override
  String get undoIssueTruncated =>
      'Изменено слишком много объектов, чтобы отменить';

  @override
  String undoMoreIssues(int count) {
    return '…и ещё $count';
  }

  @override
  String get undoAction => 'Отменить';

  @override
  String get redoAction => 'Повторить';

  @override
  String get undoForget => 'Забыть шаг';

  @override
  String get undoForgotten => 'Шаг забыт';

  @override
  String get syncTitle => 'Синхронизация папок';

  @override
  String get syncLeft => 'Левая папка';

  @override
  String get syncRight => 'Правая папка';

  @override
  String get syncSwap => 'Поменять папки местами';

  @override
  String get syncSubfolders => 'С подпапками';

  @override
  String get syncByContent => 'Сравнивать содержимое';

  @override
  String get syncFatTime => 'Не различать время до 2 с';

  @override
  String get syncHidden => 'Скрытые файлы';

  @override
  String get syncMask => 'Файлы';

  @override
  String get syncMaskHint => 'Все файлы или маска: *.jpg;*.png';

  @override
  String get syncDirection => 'Направление';

  @override
  String get syncBothWays => 'В обе стороны';

  @override
  String get syncLeftToRight => 'Слева направо';

  @override
  String get syncRightToLeft => 'Справа налево';

  @override
  String get syncDelete => 'Удалять то, чего нет в источнике';

  @override
  String get syncShow => 'Показать';

  @override
  String get syncFilterLeftOnly => 'Только слева';

  @override
  String get syncFilterRightOnly => 'Только справа';

  @override
  String get syncFilterNewer => 'Новее';

  @override
  String get syncFilterDifferent => 'Различаются';

  @override
  String get syncFilterIdentical => 'Одинаковые';

  @override
  String get syncColumnLeft => 'Слева';

  @override
  String get syncColumnRight => 'Справа';

  @override
  String syncItemsCompared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Сравнено $count объекта',
      many: 'Сравнено $count объектов',
      few: 'Сравнено $count объекта',
      one: 'Сравнён $count объект',
    );
    return '$_temp0';
  }

  @override
  String syncToRight(String count) {
    return 'Направо: $count';
  }

  @override
  String syncToLeft(String count) {
    return 'Налево: $count';
  }

  @override
  String syncToDelete(String count) {
    return 'Удалить: $count';
  }

  @override
  String syncBytes(String size) {
    return 'Скопировать $size';
  }

  @override
  String get syncNothingToDo => 'Синхронизировать нечего';

  @override
  String get syncIdentical => 'Папки одинаковы';

  @override
  String syncUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Не удалось прочитать $count папки',
      many: 'Не удалось прочитать $count папок',
      few: 'Не удалось прочитать $count папки',
      one: 'Не удалось прочитать $count папку',
    );
    return '$_temp0';
  }

  @override
  String syncError(String message) {
    return 'Не удалось сравнить: $message';
  }

  @override
  String get syncSameFolder => 'Слева и справа одна и та же папка';

  @override
  String get syncStartHint => 'Выберите папки и нажмите «Сравнить»';

  @override
  String get syncNoRows => 'С этими фильтрами показать нечего';

  @override
  String get syncCompare => 'Сравнить';

  @override
  String get syncSynchronize => 'Синхронизировать…';

  @override
  String get syncActionCopyRight => 'Копировать направо';

  @override
  String get syncActionCopyLeft => 'Копировать налево';

  @override
  String get syncActionDeleteLeft => 'Удалить слева';

  @override
  String get syncActionDeleteRight => 'Удалить справа';

  @override
  String get syncActionSkip => 'Не трогать';

  @override
  String get syncActionDefault => 'Предложенное действие';

  @override
  String get syncStateEqual => 'Одинаковые';

  @override
  String get syncStateDifferent => 'Различаются, ни один не новее';

  @override
  String get syncStateConflict => 'С одной стороны файл, с другой папка';

  @override
  String get syncStateSkipped => 'Остаётся как есть';

  @override
  String get syncConfirmTitle => 'Синхронизировать папки?';

  @override
  String syncConfirmDelete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count объекта отправятся в Корзину.',
      many: '$count объектов отправятся в Корзину.',
      few: '$count объекта отправятся в Корзину.',
      one: '$count объект отправится в Корзину.',
    );
    return '$_temp0';
  }

  @override
  String syncConfirmOverwrite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файла будут заменены; прежние версии утеряются.',
      many: '$count файлов будут заменены; прежние версии утеряются.',
      few: '$count файла будут заменены; прежние версии утеряются.',
      one: '$count файл будет заменён; прежняя версия утеряется.',
    );
    return '$_temp0';
  }

  @override
  String syncConfirmUndo(String key) {
    return 'Отмена ($key) уберёт копии в Корзину и вернёт удалённое из неё.';
  }

  @override
  String get syncSynchronizeNow => 'Синхронизировать';

  @override
  String syncKeysHint(String space, String right, String left) {
    return '$space меняет действие, $right и $left выбирают сторону';
  }

  @override
  String get checksumTitle => 'Контрольные суммы';

  @override
  String checksumVerifyTitle(String name) {
    return 'Проверка $name';
  }

  @override
  String get checksumAlgorithm => 'Алгоритм';

  @override
  String get checksumModeCalculate => 'Вычислить';

  @override
  String get checksumModeVerify => 'Проверить';

  @override
  String get checksumSubfolders => 'С подпапками';

  @override
  String get checksumExpected => 'Ожидаемая сумма';

  @override
  String get checksumExpectedHint => 'Вставьте сумму, чтобы найти её';

  @override
  String checksumMatch(String name) {
    return 'Совпадает с $name';
  }

  @override
  String checksumMatchMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Совпадает с $count файлами',
      many: 'Совпадает с $count файлами',
      few: 'Совпадает с $count файлами',
      one: 'Совпадает с $count файлом',
    );
    return '$_temp0';
  }

  @override
  String get checksumNoMatch => 'Ни у одного файла нет такой суммы';

  @override
  String get checksumColumnHash => 'Сумма';

  @override
  String get checksumColumnStatus => 'Состояние';

  @override
  String get checksumStatusOk => 'Совпадает';

  @override
  String get checksumStatusMismatch => 'Не совпадает';

  @override
  String get checksumStatusMissing => 'Нет файла';

  @override
  String get checksumStatusError => 'Не читается';

  @override
  String get checksumPending => 'В очереди';

  @override
  String checksumFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файла',
      many: '$count файлов',
      few: '$count файла',
      one: '$count файл',
      zero: 'Нет файлов',
    );
    return '$_temp0';
  }

  @override
  String checksumVerifySummary(String ok, String mismatch, String missing) {
    return 'Совпадает: $ok, не совпадает: $mismatch, нет файла: $missing';
  }

  @override
  String checksumBadLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Не разобрано $count строки',
      many: 'Не разобрано $count строк',
      few: 'Не разобраны $count строки',
      one: 'Не разобрана $count строка',
    );
    return '$_temp0';
  }

  @override
  String checksumError(String message) {
    return 'Не удалось проверить: $message';
  }

  @override
  String get checksumCopyHash => 'Копировать сумму';

  @override
  String get checksumCopyLine => 'Копировать строку';

  @override
  String get checksumCopyAll => 'Копировать всё';

  @override
  String get checksumSave => 'Сохранить файл сумм…';

  @override
  String get checksumSaveTitle => 'Сохранить файл контрольных сумм';

  @override
  String checksumSaveExists(String name) {
    return '«$name» уже существует. Заменить?';
  }

  @override
  String get checksumReplace => 'Заменить';

  @override
  String checksumSaved(String name) {
    return 'Сохранено: $name';
  }

  @override
  String checksumCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Скопировано $count суммы',
      many: 'Скопировано $count сумм',
      few: 'Скопированы $count суммы',
      one: 'Скопирована $count сумма',
    );
    return '$_temp0';
  }

  @override
  String get checksumNoFiles => 'Нет файлов для подсчёта';

  @override
  String get dupesTitle => 'Поиск дубликатов';

  @override
  String get dupesIn => 'Искать в';

  @override
  String dupesAlsoIn(String path) {
    return 'Также в $path';
  }

  @override
  String get dupesMinSize => 'Не меньше';

  @override
  String get dupesNames => 'Имена';

  @override
  String dupesScanning(String count) {
    return 'Просмотрено файлов: $count';
  }

  @override
  String dupesComparing(String done, String total) {
    return 'Сравнение файлов: $done из $total';
  }

  @override
  String dupesRead(String size) {
    return 'прочитано $size';
  }

  @override
  String dupesGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count группы дубликатов',
      many: '$count групп дубликатов',
      few: '$count группы дубликатов',
      one: '$count группа дубликатов',
      zero: 'Дубликатов нет',
    );
    return '$_temp0';
  }

  @override
  String dupesWasted(String size) {
    return 'Можно освободить $size';
  }

  @override
  String dupesGroupHeader(String size, int count) {
    return '$size × $count';
  }

  @override
  String get dupesMark => 'Отметить';

  @override
  String get dupesMarkAllButNewest => 'Все, кроме самого нового в группе';

  @override
  String get dupesMarkAllButOldest => 'Все, кроме самого старого в группе';

  @override
  String get dupesMarkAllButShortest =>
      'Все, кроме самого короткого пути в группе';

  @override
  String get dupesUnmarkAll => 'Снять все отметки';

  @override
  String dupesMarked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Отмечено $count файла',
      many: 'Отмечено $count файлов',
      few: 'Отмечено $count файла',
      one: 'Отмечен $count файл',
    );
    return '$_temp0';
  }

  @override
  String get dupesReveal => 'Показать в панели';

  @override
  String get dupesCopyPaths => 'Копировать пути';

  @override
  String dupesTrashTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Отправить $count файла в Корзину?',
      many: 'Отправить $count файлов в Корзину?',
      few: 'Отправить $count файла в Корзину?',
      one: 'Отправить $count файл в Корзину?',
    );
    return '$_temp0';
  }

  @override
  String dupesTrashBody(String size, String key) {
    return '$size освободится, когда Корзина будет очищена; отмена ($key) вернёт файлы.';
  }

  @override
  String dupesTrashAllCopies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'В $count группы отмечены все копии: ни одной не останется.',
      many: 'В $count группах отмечены все копии: ни одной не останется.',
      few: 'В $count группах отмечены все копии: ни одной не останется.',
      one: 'В $count группе отмечены все копии: ни одной не останется.',
    );
    return '$_temp0';
  }

  @override
  String get dupesNone => 'Дубликатов не найдено';

  @override
  String get dupesStartHint => 'Выберите, где искать, и нажмите «Найти»';

  @override
  String dupesError(String message) {
    return 'Не удалось найти: $message';
  }

  @override
  String dupesKeysHint(String space) {
    return '$space отмечает файл';
  }

  @override
  String get dupesMarkColumn => 'Отметка';

  @override
  String get dupesUnmark => 'Снять отметку';

  @override
  String get cmdExtractTo => 'Распаковать в…';

  @override
  String get cmdToggleFlatView => 'Плоский список';

  @override
  String get cmdEditTags => 'Теги…';

  @override
  String get archivePasswordRequired => 'Нужен пароль';

  @override
  String get archiveWrongPassword => 'Неверный пароль';

  @override
  String archiveExtractOneTitle(String name) {
    return 'Распаковать «$name» в';
  }

  @override
  String archiveExtractManyTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Распаковать $count архива в',
      many: 'Распаковать $count архивов в',
      few: 'Распаковать $count архива в',
      one: 'Распаковать $count архив в',
    );
    return '$_temp0';
  }

  @override
  String archiveExtractMembersTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Распаковать $count объекта в',
      many: 'Распаковать $count объектов в',
      few: 'Распаковать $count объекта в',
      one: 'Распаковать $count объект в',
    );
    return '$_temp0';
  }

  @override
  String get archiveIntoFolders => 'Каждый архив — в папку с его именем';

  @override
  String archiveIntoFolder(String name) {
    return 'В папку «$name»';
  }

  @override
  String get archivePasswordLabel => 'Пароль';

  @override
  String archiveWrongPasswordFor(String name) {
    return 'Этот пароль не открывает «$name»';
  }

  @override
  String get archiveExtractAction => 'Распаковать';

  @override
  String get archiveNoArchives => 'Среди объектов нет архивов';

  @override
  String archivePasswordTitle(String name) {
    return '«$name» зашифрован';
  }

  @override
  String get archivePasswordMessage => 'Введите пароль, чтобы открыть архив.';

  @override
  String get archivePasswordOpen => 'Открыть';

  @override
  String get archiveEnterPassword => 'Ввести пароль…';

  @override
  String archiveDestinationHint(String key) {
    return '$key дополняет имя папки';
  }

  @override
  String get flatCapsule => 'Плоский';

  @override
  String get flatLeave => 'Вернуться к папке';

  @override
  String get flatWalking => 'Чтение дерева папки';

  @override
  String flatFileCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString файла',
      many: '$countString файлов',
      few: '$countString файла',
      one: '$countString файл',
      zero: 'нет файлов',
    );
    return '$_temp0';
  }

  @override
  String flatCappedCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'первые $countString файла',
      many: 'первые $countString файлов',
      few: 'первые $countString файла',
      one: 'первый $countString файл',
    );
    return '$_temp0';
  }

  @override
  String flatRowLabel(String name, String folder) {
    return '$name, в $folder';
  }

  @override
  String get tagsMenuTitle => 'Теги';

  @override
  String get tagColorRed => 'Красный';

  @override
  String get tagColorOrange => 'Оранжевый';

  @override
  String get tagColorYellow => 'Желтый';

  @override
  String get tagColorGreen => 'Зеленый';

  @override
  String get tagColorBlue => 'Синий';

  @override
  String get tagColorPurple => 'Лиловый';

  @override
  String get tagColorGray => 'Серый';

  @override
  String get tagsNew => 'Новый тег…';

  @override
  String get tagsNewTitle => 'Новый тег';

  @override
  String get tagsNameLabel => 'Имя';

  @override
  String get tagsColorLabel => 'Цвет';

  @override
  String get tagsColorNone => 'Без цвета';

  @override
  String get tagsAdd => 'Добавить';

  @override
  String tagsList(String first, String second) {
    return '$first, $second';
  }

  @override
  String tagsRowLabel(String label, String tags) {
    return '$label, теги: $tags';
  }

  @override
  String tagsFailed(int count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Не удалось изменить теги $count объекта: $reason',
      many: 'Не удалось изменить теги $count объектов: $reason',
      few: 'Не удалось изменить теги $count объектов: $reason',
      one: 'Не удалось изменить теги $count объекта: $reason',
    );
    return '$_temp0';
  }

  @override
  String get findSpotlight => 'Искать по индексу Spotlight';

  @override
  String get findSpotlightNote =>
      'Быстрее, но Spotlight не видит системные и скрытые папки, а также папки, исключенные в Системных настройках.';

  @override
  String get findSpotlightFailed =>
      'Spotlight не смог искать здесь — папки просмотрены напрямую.';

  @override
  String get noticeNotInFlat =>
      'Это работает с содержимым одной папки: сначала выйдите из плоского списка';

  @override
  String get cmdConnectToServer => 'Подключиться к серверу…';

  @override
  String get cmdDisconnectServer => 'Отключиться';

  @override
  String get errorAuthFailed => 'Сервер не принял вход';

  @override
  String get errorHostUnreachable => 'Сервер недоступен';

  @override
  String get errorTimedOut => 'Сервер не ответил вовремя';

  @override
  String get errorHostKeyUnknown => 'Ключу сервера не доверились';

  @override
  String get errorHostKeyChanged => 'Ключ сервера изменился';

  @override
  String get errorConnectionLost => 'Связь с сервером прервалась';

  @override
  String get errorNotConnected => 'Нет подключения к серверу';

  @override
  String get errorCertificateInvalid => 'Сертификату сервера нет доверия';

  @override
  String get networkConnectTitle => 'Подключение к серверу';

  @override
  String get networkAddressLabel => 'Адрес';

  @override
  String get networkAddressHint => 'sftp://пользователь@хост/папка';

  @override
  String get networkAddressNote =>
      'SFTP, FTP, FTPS (ftps://), WebDAV (dav:// или davs://, http://, https://).';

  @override
  String get networkSavedServers => 'Сохранённые серверы';

  @override
  String get networkNoServers =>
      'Сохранённых серверов пока нет. Введите адрес выше или добавьте сервер.';

  @override
  String get networkAddServer => 'Добавить сервер…';

  @override
  String get networkEditServer => 'Изменить…';

  @override
  String get networkRemoveServer => 'Удалить';

  @override
  String networkRemoveServerTitle(String name) {
    return 'Удалить «$name»?';
  }

  @override
  String get networkRemoveServerMessage =>
      'Сохранённый пароль останется в связке ключей, пока вы не забудете его в настройках сервера.';

  @override
  String get networkConnect => 'Подключиться';

  @override
  String networkConnecting(String server) {
    return 'Подключение к $server…';
  }

  @override
  String get networkInsecure =>
      'Без шифрования: имена, пароли и файлы идут по сети открыто.';

  @override
  String get networkServerNew => 'Новый сервер';

  @override
  String get networkServerEdit => 'Настройки сервера';

  @override
  String get networkFieldName => 'Название';

  @override
  String get networkFieldNameHint => 'Если пусто — имя хоста';

  @override
  String get networkFieldProtocol => 'Протокол';

  @override
  String get networkFieldHost => 'Хост';

  @override
  String get networkFieldPort => 'Порт';

  @override
  String get networkFieldUser => 'Пользователь';

  @override
  String get networkFieldUserHint => 'Если пусто — анонимно';

  @override
  String get networkFieldFolder => 'Папка';

  @override
  String get networkFieldFolderHint => 'Начальная папка сервера';

  @override
  String get networkFieldAuth => 'Вход';

  @override
  String get networkFieldKey => 'Файл ключа';

  @override
  String get networkFieldKeyHint => '~/.ssh/id_ed25519';

  @override
  String get networkAuthAutomatic => 'Ключи или пароль';

  @override
  String get networkAuthPassword => 'Пароль';

  @override
  String get networkAuthKey => 'Файл ключа';

  @override
  String get networkAuthAgent => 'SSH-агент';

  @override
  String get networkProtocolSftp => 'SFTP (SSH)';

  @override
  String get networkProtocolFtp => 'FTP';

  @override
  String get networkProtocolFtps => 'FTPS (FTP с TLS)';

  @override
  String get networkProtocolDav => 'WebDAV (HTTP)';

  @override
  String get networkProtocolDavs => 'WebDAV (HTTPS)';

  @override
  String get networkHostRequired => 'Укажите имя или адрес сервера';

  @override
  String get networkPortInvalid => 'Порт — число от 1 до 65535';

  @override
  String get networkForgetPassword => 'Забыть сохранённый пароль';

  @override
  String networkPasswordForgotten(String server) {
    return 'Сохранённый пароль для $server забыт';
  }

  @override
  String networkPasswordTitle(String server) {
    return 'Вход на $server';
  }

  @override
  String networkPasswordMessage(String user) {
    return 'Введите пароль пользователя $user.';
  }

  @override
  String get networkPasswordWrong => 'Пароль не подошёл. Попробуйте ещё раз.';

  @override
  String get networkPasswordLabel => 'Пароль';

  @override
  String get networkRememberPassword => 'Запомнить в системной связке ключей';

  @override
  String get networkPassphraseTitle => 'Разблокировать ключ';

  @override
  String networkPassphraseMessage(String key) {
    return 'Ключ $key защищён паролем.';
  }

  @override
  String get networkPassphraseWrong =>
      'Пароль не открыл ключ. Попробуйте ещё раз.';

  @override
  String get networkPassphraseLabel => 'Пароль ключа';

  @override
  String networkPromptsTitle(String server) {
    return 'Вход на $server';
  }

  @override
  String get networkContinue => 'Продолжить';

  @override
  String get networkHostKeyTitle => 'Незнакомый сервер';

  @override
  String networkHostKeyMessage(String host, String algorithm) {
    return 'Ferryx ещё не подключался к $host. Отпечаток его ключа $algorithm:';
  }

  @override
  String get networkHostKeyAdvice =>
      'Доверяйте, только если отпечаток совпадает с тем, что сообщил администратор сервера.';

  @override
  String get networkHostKeyRemember => 'Запомнить ключ';

  @override
  String get networkHostKeyTrust => 'Доверять';

  @override
  String get networkHostKeyChangedTitle => 'Внимание: ключ сервера изменился';

  @override
  String networkHostKeyChangedMessage(String host) {
    return '$host показывает не тот ключ, что записан. Возможно, соединение перехватывают — или сервер переустановили. Ferryx не будет подключаться.';
  }

  @override
  String get networkHostKeyChangedAdvice =>
      'Если администратор сервера подтвердит новый ключ, удалите старый из файла known_hosts, названного ниже, и подключитесь снова.';

  @override
  String networkStateConnected(String server) {
    return 'Подключено к $server';
  }

  @override
  String networkStateLost(String server) {
    return 'Связь с $server прервалась; следующее действие попробует снова';
  }

  @override
  String networkStateClosed(String server) {
    return 'Нет подключения к $server';
  }

  @override
  String networkStateInsecure(String state) {
    return '$state (без шифрования)';
  }

  @override
  String get networkReconnect => 'Подключиться снова';

  @override
  String networkDisconnected(String server) {
    return 'Отключено от $server';
  }

  @override
  String get networkNotOnServer =>
      'Это работает только с файлами на этом компьютере';

  @override
  String get networkNoTrash =>
      'С сервера объекты удаляются насовсем: корзины там нет.';

  @override
  String networkOpenedCopy(String name) {
    return 'Открыта копия «$name»: изменения в ней не отправляются на сервер';
  }

  @override
  String networkNotAnAddress(String text) {
    return 'Это не адрес сервера: $text';
  }

  @override
  String get networkGoToServers => 'Серверы';

  @override
  String get networkNotRemote => 'Панель не на сервере';
}
