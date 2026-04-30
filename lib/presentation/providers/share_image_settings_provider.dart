import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';

class ShareImageSettings {
  const ShareImageSettings({
    this.stripMetadataForCopyAndDrag = false,
  });

  final bool stripMetadataForCopyAndDrag;

  ShareImageSettings copyWith({
    bool? stripMetadataForCopyAndDrag,
  }) {
    return ShareImageSettings(
      stripMetadataForCopyAndDrag:
          stripMetadataForCopyAndDrag ?? this.stripMetadataForCopyAndDrag,
    );
  }
}

final shareImageSettingsProvider =
    NotifierProvider<ShareImageSettingsNotifier, ShareImageSettings>(
  ShareImageSettingsNotifier.new,
);

class ShareImageSettingsNotifier extends Notifier<ShareImageSettings> {
  LocalStorageService get _storage => ref.read(localStorageServiceProvider);

  @override
  ShareImageSettings build() {
    return ShareImageSettings(
      stripMetadataForCopyAndDrag: _storage.getSetting<bool>(
            StorageKeys.shareStripMetadata,
            defaultValue: false,
          ) ??
          false,
    );
  }

  Future<void> setStripMetadataForCopyAndDrag(bool value) async {
    state = state.copyWith(stripMetadataForCopyAndDrag: value);
    await _storage.setSetting(StorageKeys.shareStripMetadata, value);
  }
}
