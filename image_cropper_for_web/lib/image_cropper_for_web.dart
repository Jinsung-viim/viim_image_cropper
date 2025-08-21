library image_cropper_for_web;

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:image_cropper_for_web/src/cropper_dialog.dart';
import 'package:image_cropper_for_web/src/cropper_page.dart';
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'src/interop/cropper_interop.dart';

/// The web implementation of [ImageCropperPlatform].
///
/// This class implements the `package:image_picker` functionality for the web.
class ImageCropperPlugin extends ImageCropperPlatform {
  static Cropper? _cropper; // Web Cropper.js 인스턴스 캐싱

  /// Registers this class as the default instance of [ImageCropperPlatform].
  static void registerWith(Registrar registrar) {
    ImageCropperPlatform.instance = ImageCropperPlugin();
  }

  static int _nextIFrameId = 0;

  @override
  Future<CroppedFile?> cropImage({
    required String sourcePath,
    int? maxWidth,
    int? maxHeight,
    CropAspectRatio? aspectRatio,
    ImageCompressFormat compressFormat = ImageCompressFormat.jpg,
    int compressQuality = 90,
    List<PlatformUiSettings>? uiSettings,
  }) async {
    WebUiSettings? webSettings;
    for (final settings in uiSettings ?? <PlatformUiSettings>[]) {
      if (settings is WebUiSettings) {
        webSettings = settings;
        break;
      }
    }
    if (webSettings == null) {
      assert(true, 'must provide WebUiSettings to run on Web');
      throw 'must provide WebUiSettings to run on Web';
    }

    final context = webSettings.context;
    final cropperWidth = webSettings.size?.width ?? 500;
    final cropperHeight = webSettings.size?.height ?? 500;

    final div = web.HTMLDivElement()
      ..id = 'cropperView_${_nextIFrameId++}'
      ..style.width = '100%'
      ..style.height = '100%';
    final image = web.HTMLImageElement()
      ..src = sourcePath
      ..style.maxWidth = '100%'
      ..style.display = 'block';
    div.appendChild(image);

    final options = CropperOptions(
      dragMode: webSettings.dragMode != null ? webSettings.dragMode!.value : 'crop',
      viewMode: webSettings.viewwMode != null ? webSettings.viewwMode!.value : 0,
      initialAspectRatio: webSettings.initialAspectRatio,
      aspectRatio: aspectRatio != null ? aspectRatio.ratioX / aspectRatio.ratioY : null,
      checkCrossOrigin: webSettings.checkCrossOrigin ?? true,
      checkOrientation: webSettings.checkOrientation ?? true,
      modal: webSettings.modal ?? true,
      guides: webSettings.guides ?? true,
      center: webSettings.center ?? true,
      highlight: webSettings.highlight ?? true,
      background: webSettings.background ?? true,
      movable: webSettings.movable ?? true,
      rotatable: webSettings.rotatable ?? true,
      scalable: webSettings.scalable ?? true,
      zoomable: webSettings.zoomable ?? true,
      zoomOnTouch: webSettings.zoomOnTouch ?? true,
      zoomOnWheel: webSettings.zoomOnWheel ?? true,
      wheelZoomRatio: webSettings.wheelZoomRatio ?? 0.1,
      cropBoxMovable: webSettings.cropBoxMovable ?? true,
      cropBoxResizable: webSettings.cropBoxResizable ?? true,
      toggleDragModeOnDblclick: webSettings.toggleDragModeOnDblclick ?? true,
      minContainerWidth: webSettings.minContainerWidth ?? 200,
      minContainerHeight: webSettings.minContainerHeight ?? 100,
      minCropBoxWidth: webSettings.minCropBoxWidth ?? 0,
      minCropBoxHeight: webSettings.minCropBoxHeight ?? 0,
    );
    // Cropper? cropper;
    initializer() => Future.delayed(
          const Duration(milliseconds: 0),
          () {
            // assert(_cropper == null, 'cropper was already initialized');
            _cropper = Cropper(image, options);
          },
        );

    final viewType = 'plugins.hunghd.vn/cropper-view-${Uri.encodeComponent(sourcePath)}';

    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) => div);

    final cropperWidget = HtmlElementView(
      key: ValueKey(sourcePath),
      viewType: viewType,
    );

    Future<String?> doCrop() async {
      if (_cropper != null) {
        final croppedOptions = (maxWidth != null || maxHeight != null || compressFormat == ImageCompressFormat.jpg)
            ? GetCroppedCanvasOptions()
            : null;
        if (maxWidth != null) {
          croppedOptions!.maxWidth = maxWidth;
        }
        if (maxHeight != null) {
          croppedOptions!.maxHeight = maxHeight;
        }
        if (compressFormat == ImageCompressFormat.jpg) {
          croppedOptions!.fillColor = '#fff';
        }
        final result =
            croppedOptions != null ? _cropper!.getCroppedCanvas(croppedOptions) : _cropper!.getCroppedCanvas();
        final completer = Completer<String>();
        final mimeType = compressFormat == ImageCompressFormat.png ? 'image/png' : 'image/jpeg';
        result.toBlob(
          (web.Blob blob) {
            completer.complete(web.URL.createObjectURL(blob));
          }.toJS,
          mimeType,
        );
        final url = await completer.future;
        _cropper = null; // 크랍 작업 후 인스턴스 해제
        return url;
      } else {
        return Future.error('cropper has not been initialized');
      }
    }

    void doRotate(RotationAngle angle) {
      if (_cropper == null) throw 'cropper has not been initialized';
      _cropper?.rotate(rotationAngleToNumber(angle));
    }

    void doScale(num value) {
      if (_cropper == null) throw 'cropper has not been initialized';
      _cropper?.scale(value);
    }

    if (webSettings.presentStyle == WebPresentStyle.page) {
      PageRoute<String> pageRoute;
      if (webSettings.customRouteBuilder != null) {
        pageRoute = webSettings.customRouteBuilder!(
          cropperWidget,
          initializer,
          doCrop,
          doRotate,
          doScale,
        );
      } else {
        pageRoute = MaterialPageRoute(
          builder: (c) => CropperPage(
            cropper: cropperWidget,
            initCropper: initializer,
            crop: doCrop,
            rotate: doRotate,
            scale: doScale,
            cropperContainerWidth: cropperWidth * 1.0,
            cropperContainerHeight: cropperHeight * 1.0,
            translations: webSettings?.translations ?? const WebTranslations.en(),
            themeData: webSettings?.themeData,
          ),
        );
      }
      final result = await Navigator.of(context).push<String>(pageRoute);

      return result != null ? CroppedFile(result) : null;
    } else {
      Widget cropperDialog;
      if (webSettings.customDialogBuilder != null) {
        cropperDialog = webSettings.customDialogBuilder!(
          cropperWidget,
          initializer,
          doCrop,
          doRotate,
          doScale,
        );
      } else {
        cropperDialog = CropperDialog(
          cropper: cropperWidget,
          initCropper: initializer,
          crop: doCrop,
          rotate: doRotate,
          scale: doScale,
          cropperContainerWidth: cropperWidth * 1.0,
          cropperContainerHeight: cropperHeight * 1.0,
          translations: webSettings.translations ?? const WebTranslations.en(),
          themeData: webSettings.themeData,
        );
      }
      final result = await showDialog<String?>(
        context: context,
        barrierColor: webSettings.barrierColor,
        barrierDismissible: false,
        builder: (_) => cropperDialog,
      );

      return result != null ? CroppedFile(result) : null;
    }
  }

  @override
  Future<CroppedFile?> recoverImage() async {
    return null;
  }

  @override
  Future<void> setAspectRatio(double ratio) async {
    if (_cropper == null) {
      throw 'Cropper not initialized yet';
    }
    _cropper!.setAspectRatio(ratio);
  }
}
