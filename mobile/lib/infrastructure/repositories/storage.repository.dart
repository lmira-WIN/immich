// ignore_for_file: avoid_slow_async_io

import 'dart:io';

import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';

class StorageRepository {
  final log = Logger('StorageRepository');

  StorageRepository();

  Future<File?> getFileForAsset(String assetId) async {
    File? file;
    final log = Logger('StorageRepository');

    try {
      final entity = await AssetEntity.fromId(assetId);
      file = await entity?.originFile;
      if (file == null) {
        log.warning("Cannot get file for asset $assetId");
        return null;
      }

      final exists = await file.exists();
      if (!exists) {
        log.warning("File for asset $assetId does not exist");
        return null;
      }
    } catch (error, stackTrace) {
      log.warning("Error getting file for asset $assetId", error, stackTrace);
    }
    return file;
  }

  // TODO(agg23): Unify these methods
  Future<File?> getMotionFileForAsset(LocalAsset asset) async {
    File? file;
    final log = Logger('StorageRepository');

    try {
      final entity = await AssetEntity.fromId(asset.id);
      file = await entity?.originFileWithSubtype;
      if (file == null) {
        log.warning(
          "Cannot get motion file for asset ${asset.id}, name: ${asset.name}, created on: ${asset.createdAt}",
        );
        return null;
      }

      final exists = await file.exists();
      if (!exists) {
        log.warning("Motion file for asset ${asset.id} does not exist");
        return null;
      }
    } catch (error, stackTrace) {
      log.warning(
        "Error getting motion file for asset ${asset.id}, name: ${asset.name}, created on: ${asset.createdAt}",
        error,
        stackTrace,
      );
    }
    return file;
  }

  Future<AssetEntity?> getAssetEntityForAsset(LocalAsset asset) async {
    final log = Logger('StorageRepository');

    AssetEntity? entity;

    try {
      entity = await AssetEntity.fromId(asset.id);
      if (entity == null) {
        log.warning(
          "Cannot get AssetEntity for asset ${asset.id}, name: ${asset.name}, created on: ${asset.createdAt}",
        );
      }
    } catch (error, stackTrace) {
      log.warning(
        "Error getting AssetEntity for asset ${asset.id}, name: ${asset.name}, created on: ${asset.createdAt}",
        error,
        stackTrace,
      );
    }
    return entity;
  }

  Future<bool> isAssetAvailableLocally(String assetId) async {
    try {
      final entity = await AssetEntity.fromId(assetId);
      if (entity == null) {
        log.warning("Cannot get AssetEntity for asset $assetId");
        return false;
      }

      return await entity.isLocallyAvailable(isOrigin: true);
    } catch (error, stackTrace) {
      log.warning("Error checking if asset is locally available $assetId", error, stackTrace);
      return false;
    }
  }

  Future<File?> loadFileFromCloud(String assetId, {PMProgressHandler? progressHandler}) async {
    try {
      final entity = await AssetEntity.fromId(assetId);
      if (entity == null) {
        log.warning("Cannot get AssetEntity for asset $assetId");
        return null;
      }

      await _logPhotoKitState(entity, assetId, "before loadFile");
      final file = await entity.loadFile(progressHandler: progressHandler);

      if (file == null) {
        log.warning("PhotoKit returned null from loadFile for asset $assetId");
      } else {
        final exists = await file.exists();
        log.info("PhotoKit returned file for asset $assetId: pathExists=$exists path=$file");
      }

      return file;
    } catch (error, stackTrace) {
      log.warning("Error loading file from cloud for asset $assetId", error, stackTrace);
      try {
        final entity = await AssetEntity.fromId(assetId);
        if (entity != null) {
          await _logPhotoKitState(entity, assetId, "after loadFile error");
        }
      } catch (diagnosticError, diagnosticStack) {
        log.warning(
          "PhotoKit diagnostic failed for asset $assetId",
          diagnosticError,
          diagnosticStack,
        );
      }
      return null;
    }
  }

  Future<File?> loadMotionFileFromCloud(String assetId, {PMProgressHandler? progressHandler}) async {
    try {
      final entity = await AssetEntity.fromId(assetId);
      if (entity == null) {
        log.warning("Cannot get AssetEntity for asset $assetId");
        return null;
      }

      await _logPhotoKitState(entity, assetId, "before loadMotionFile");
      final file = await entity.loadFile(withSubtype: true, progressHandler: progressHandler);

      if (file == null) {
        log.warning("PhotoKit returned null from loadFile(withSubtype) for asset $assetId");
      } else {
        final exists = await file.exists();
        log.info("PhotoKit returned motion file for asset $assetId: pathExists=$exists path=$file");
      }

      return file;
    } catch (error, stackTrace) {
      log.warning("Error loading motion file from cloud for asset $assetId", error, stackTrace);
      return null;
    }
  }

  Future<void> _logPhotoKitState(AssetEntity entity, String assetId, String stage) async {
    if (!CurrentPlatform.isIOS) {
      return;
    }

    try {
      final locallyAvailable = await entity.isLocallyAvailable(isOrigin: true);
      final exists = await entity.exists;
      final mimeType = await entity.mimeTypeAsync;

      String? cloudIdentifier;
      bool? hasAdjustments;
      try {
        cloudIdentifier = await entity.darwin.cloudIdentifier;
        hasAdjustments = await entity.darwin.hasAdjustments;
      } catch (error, stackTrace) {
        log.fine(
          "Optional Darwin diagnostics failed for $assetId at $stage",
          error,
          stackTrace,
        );
      }

      log.info(
        "PhotoKit state [$stage] id=$assetId "
        "exists=$exists "
        "locallyAvailableOrigin=$locallyAvailable "
        "type=${entity.type} "
        "subtype=${entity.subtype} "
        "title=${entity.title} "
        "mimeType=$mimeType "
        "width=${entity.width} "
        "height=${entity.height} "
        "duration=${entity.duration} "
        "cloudIdentifier=${cloudIdentifier ?? "(null)"} "
        "hasAdjustments=${hasAdjustments ?? "unknown"}",
      );
    } catch (error, stackTrace) {
      log.warning("PhotoKit diagnostic state failed for asset $assetId at $stage", error, stackTrace);
    }
  }

  Future<void> clearCache() async {
    final log = Logger('StorageRepository');

    try {
      await PhotoManager.clearFileCache();
    } catch (error, stackTrace) {
      log.warning("Error clearing cache", error, stackTrace);
    }

    if (!CurrentPlatform.isIOS) {
      return;
    }

    try {
      if (await Directory.systemTemp.exists()) {
        await Directory.systemTemp.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      log.warning("Error deleting temporary directory", error, stackTrace);
    }
  }
}
