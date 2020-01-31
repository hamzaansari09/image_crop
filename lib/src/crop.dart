part of image_crop;

const _kCropGridColumnCount = 3;
const _kCropGridRowCount = 3;
const _kCropGridColor = const Color.fromRGBO(0xd0, 0xd0, 0xd0, 0.9);
const _kCropOverlayColor = const Color.fromRGBO(0x0, 0x0, 0x0, 0.3);
const _kCropHandleSize = 10.0;
const _kCropHandleHitSize = 48.0;
const _kCropMinFraction = 0.2;
const _kCropBorderColor = Color(0xff55bbea);

enum _CropAction { none, cropping, moving }
enum _CropHandleSide {
  none,
  top,
  left,
  right,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight
}

class Crop extends StatefulWidget {
  final ImageProvider image;
  final double aspectRatio;
  final bool alwaysShowGrid;
  final ImageErrorListener onImageError;

  const Crop({
    Key key,
    this.image,
    this.aspectRatio,
    this.alwaysShowGrid: false,
    this.onImageError,
  })  : assert(image != null),
        assert(alwaysShowGrid != null),
        super(key: key);

  Crop.file(
    File file, {
    Key key,
    this.aspectRatio,
    this.alwaysShowGrid: false,
    this.onImageError,
  })  : image = FileImage(file),
        assert(alwaysShowGrid != null),
        super(key: key);

  @override
  State<StatefulWidget> createState() => CropState();

  static CropState of(BuildContext context) {
    return context.findAncestorStateOfType<CropState>();
  }
}

class CropState extends State<Crop> with TickerProviderStateMixin, Drag {
  final _surfaceKey = GlobalKey();
  AnimationController _activeController;
  AnimationController _settleController;
  ImageStream _imageStream;
  ui.Image _image;
  double _ratio;
  Rect _view;
  Rect _area;
  Rect _previousArea;
  Offset _lastFocalPoint;
  _CropAction _action;
  _CropHandleSide _handle;
  Tween<Rect> _viewTween;
  ImageStreamListener _imageListener;

  Rect get area {
    return _view.isEmpty
        ? null
        : Rect.fromLTWH(
            _area.left * _view.width - _view.left,
            _area.top * _view.height - _view.top,
            _area.width * _view.width,
            _area.height * _view.height,
          );
  }

  bool get _isEnabled => !_view.isEmpty && _image != null;

  @override
  void initState() {
    super.initState();
    _area = Rect.zero;
    _view = Rect.zero;
    _previousArea = Rect.zero;
    _ratio = 1.0;
    _lastFocalPoint = Offset.zero;
    _action = _CropAction.none;
    _handle = _CropHandleSide.none;
    _activeController = AnimationController(
      vsync: this,
      value: widget.alwaysShowGrid ? 1.0 : 0.0,
    )..addListener(() => setState(() {}));
    _settleController = AnimationController(vsync: this)
      ..addListener(_settleAnimationChanged);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageListener);
    _activeController.dispose();
    _settleController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getImage();
  }

  void _getImage({bool force: false}) {
    final oldImageStream = _imageStream;
    _imageStream = widget.image.resolve(createLocalImageConfiguration(context));
    if (_imageStream.key != oldImageStream?.key || force) {
      oldImageStream?.removeListener(_imageListener);
      _imageListener =
          ImageStreamListener(_updateImage, onError: widget.onImageError);
      _imageStream.addListener(_imageListener);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints.expand(),
      child: GestureDetector(
        key: _surfaceKey,
        behavior: HitTestBehavior.opaque,
        onScaleStart: _isEnabled ? _handleScaleStart : null,
        onScaleUpdate: _isEnabled ? _handleScaleUpdate : null,
        onScaleEnd: _isEnabled ? _handleScaleEnd : null,
        child: CustomPaint(
          painter: _CropPainter(
            image: _image,
            ratio: _ratio,
            view: _view,
            area: _area,
            active: _activeController.value,
          ),
        ),
      ),
    );
  }

  void _activate() {
    _activeController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 250),
    );
  }

  void _deactivate() {
    if (!widget.alwaysShowGrid) {
      _activeController.animateTo(
        0.0,
        curve: Curves.fastOutSlowIn,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  Size get _boundaries =>
      _surfaceKey.currentContext.size -
      Offset(_kCropHandleSize, _kCropHandleSize);

  Offset _getLocalPoint(Offset point) {
    final RenderBox box = _surfaceKey.currentContext.findRenderObject();
    return box.globalToLocal(point);
  }

  void _settleAnimationChanged() {
    setState(() {
      _view = _viewTween.transform(_settleController.value);
    });
  }

  Rect _calculateDefaultArea({
    int imageWidth,
    int imageHeight,
    double viewWidth,
    double viewHeight,
  }) {
    if (imageWidth == null || imageHeight == null) {
      return Rect.zero;
    }
    final ascpectRatio = max( (imageWidth / imageHeight), 1);
    final width = 1.0;
    final height = (imageWidth * viewWidth * width) /
        (imageHeight * viewHeight * ascpectRatio);
    return Rect.fromLTWH((1.0 - width) / 2, (1.0 - height) / 2, width, height);
  }

  void _updateImage(ImageInfo imageInfo, bool synchronousCall) {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      setState(() {
        _image = imageInfo.image;
        _ratio = _boundaries.width / _image.width;

        final viewWidth = _boundaries.width / (_image.width * _ratio);
        final viewHeight = _boundaries.height / (_image.height * _ratio);

        _area = _calculateDefaultArea(
          viewWidth: viewWidth,
          viewHeight: viewHeight,
          imageWidth: _image.width,
          imageHeight: _image.height,
        );
        _view = Rect.fromLTWH(
          (viewWidth - 1.0) / 2,
          (viewHeight - 1.0) / 2,
          viewWidth,
          viewHeight,
        );
        _previousArea = _area;
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  _CropHandleSide _hitCropHandle(Offset localPoint) {
    final boundaries = _boundaries;
    final viewRect = Rect.fromLTWH(
      _boundaries.width * _area.left,
      boundaries.height * _area.top,
      boundaries.width * _area.width,
      boundaries.height * _area.height,
    ).deflate(_kCropHandleSize / 2);

    if (Rect.fromLTWH(
      viewRect.left + _kCropHandleHitSize,
      viewRect.bottom - _kCropHandleHitSize / 2,
      viewRect.width - 2 * _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.bottom;
    }

    if (Rect.fromLTWH(
      viewRect.left + _kCropHandleHitSize,
      viewRect.top - _kCropHandleHitSize / 2,
      viewRect.width - 2 * _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.top;
    }

    if (Rect.fromLTWH(
      viewRect.left - _kCropHandleHitSize / 2,
      viewRect.top + _kCropHandleHitSize,
      _kCropHandleHitSize,
      viewRect.height - 2 * _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.left;
    }

    if (Rect.fromLTWH(
      viewRect.right - _kCropHandleHitSize / 2,
      viewRect.top + _kCropHandleHitSize,
      _kCropHandleHitSize,
      viewRect.height - 2 * _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.right;
    }

    if (Rect.fromLTWH(
      viewRect.left - _kCropHandleHitSize / 2,
      viewRect.top - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.topLeft;
    }

    if (Rect.fromLTWH(
      viewRect.right - _kCropHandleHitSize / 2,
      viewRect.top - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.topRight;
    }

    if (Rect.fromLTWH(
      viewRect.left - _kCropHandleHitSize / 2,
      viewRect.bottom - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.bottomLeft;
    }

    if (Rect.fromLTWH(
      viewRect.right - _kCropHandleHitSize / 2,
      viewRect.bottom - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.bottomRight;
    }

    return _CropHandleSide.none;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _settleController.stop(canceled: false);
    _lastFocalPoint = details.focalPoint;
    _action = _CropAction.none;
    _handle = _hitCropHandle(_getLocalPoint(details.focalPoint));

    if (_handle != _CropHandleSide.none) {
      _activate();
    }
  }

  bool _shouldMoveCropRect(Offset localPoint) {
    final boundaries = _boundaries;
    final viewRect = Rect.fromLTWH(
      _boundaries.width * _area.left,
      boundaries.height * _area.top,
      boundaries.width * _area.width,
      boundaries.height * _area.height,
    );

    return Rect.fromLTWH(
      viewRect.left + _kCropHandleHitSize/2,
      viewRect.bottom - _kCropHandleHitSize/2,
      viewRect.width - _kCropHandleHitSize,
      viewRect.height - _kCropHandleHitSize,
    ).contains(localPoint);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _deactivate();
  }

  void _updateArea({double left, double top, double right, double bottom}) {
    var areaLeft = _area.left + (left ?? 0.0);
    var areaTop = _area.top + (top ?? 0.0);
    var areaRight = _area.right + (right ?? 0.0);
    var areaBottom = _area.bottom + (bottom ?? 0.0);

    // ensure minimum rectangle
    if (areaRight - areaLeft < _kCropMinFraction) {
      if (left != null) {
        areaLeft = areaRight - _kCropMinFraction;
      } else {
        areaRight = areaLeft + _kCropMinFraction;
      }
    }

    if (areaBottom - areaTop < _kCropMinFraction) {
      if (top != null) {
        areaTop = areaBottom - _kCropMinFraction;
      } else {
        areaBottom = areaTop + _kCropMinFraction;
      }
    }

    // adjust to aspect ratio if needed
    if (widget.aspectRatio != null && widget.aspectRatio > 0.0) {
      final width = areaRight - areaLeft;
      final height = (_image.width * _view.width * width) /
          (_image.height * _view.height * widget.aspectRatio);

      if (top != null) {
        areaTop = areaBottom - height;
        if (areaTop < 0.0) {
          areaTop = 0.0;
          areaBottom = height;
        }
      } else {
        areaBottom = areaTop + height;
        if (areaBottom > 1.0) {
          areaTop = 1.0 - height;
          areaBottom = 1.0;
        }
      }
    }

    // ensure to remain within bounds of the view
    if (areaLeft < 0.0) {
      areaLeft = 0.0;
      areaRight = _area.width;
    } else if (areaRight > 1.0) {
      areaLeft = 1.0 - _area.width;
      areaRight = 1.0;
    }

    if (areaTop < 0.0) {
      areaTop = 0.0;
      areaBottom = _area.height;
    } else if (areaBottom > 1.0) {
      areaTop = 1.0 - _area.height;
      areaBottom = 1.0;
    }

    if (areaLeft < _previousArea.left) {
      areaLeft = _area.left;
      areaRight = _area.width;
    } else if (areaRight > _previousArea.right) {
      areaLeft = _area.right - _area.width;
      areaRight = _area.right;
    }

    if (areaTop < _previousArea.top) {
      areaTop = _area.top;
      areaBottom = _area.bottom;
    } else if (areaBottom > _previousArea.bottom) {
      areaTop = _area.bottom - _area.height;
      areaBottom = _area.bottom;
    }

    setState(() {
      _area = Rect.fromLTRB(areaLeft, areaTop, areaRight, areaBottom);
    });
  }

  void _moveCropArea({double x, double y}) {
    var areaLeft = _area.left + (x ?? 0.0);
    var areaTop = _area.top + (y ?? 0.0);
    var areaRight = _area.right + (x ?? 0.0);
    var areaBottom = _area.bottom + (y ?? 0.0);

    // ensure to remain within bounds of the view
    if (areaLeft < 0.0 || areaRight > 1.0 || areaTop < _previousArea.top || areaBottom > _previousArea.bottom) {
      return;
    } 
    setState(() {
      _area = Rect.fromLTRB(areaLeft, areaTop, areaRight, areaBottom);
    });
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_action == _CropAction.none){
      if (_handle == _CropHandleSide.none) {
        _action = _CropAction.moving;
      } else {
        _action = _CropAction.cropping;
      }
    }

    if (_action == _CropAction.cropping) {
      final delta = details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;

      final dx = delta.dx / _boundaries.width;
      final dy = delta.dy / _boundaries.height;

      if (_handle == _CropHandleSide.top) {
        _updateArea(top: dy);
      } else if (_handle == _CropHandleSide.left) {
        _updateArea(left: dx);
      } else if (_handle == _CropHandleSide.right) {
        _updateArea(right: dx);
      } else if (_handle == _CropHandleSide.bottom) {
        _updateArea(bottom: dy);
      } else if (_handle == _CropHandleSide.topLeft) {
        _updateArea(left: dx, top: dy);
      } else if (_handle == _CropHandleSide.topRight) {
        _updateArea(top: dy, right: dx);
      } else if (_handle == _CropHandleSide.bottomLeft) {
        _updateArea(left: dx, bottom: dy);
      } else if (_handle == _CropHandleSide.bottomRight) {
        _updateArea(right: dx, bottom: dy);
      }
    } else if (_action == _CropAction.moving && _shouldMoveCropRect(details.focalPoint)) {
      final delta = details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;
      final dx = delta.dx / _boundaries.width;
      final dy = delta.dy / _boundaries.height;
      //TODO: handle crop box movement
      // _moveCropArea(x: dx , y: dy);
    } 
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect view;
  final double ratio;
  final Rect area;
  final double active;

  _CropPainter({
    this.image,
    this.view,
    this.ratio,
    this.area,
    this.active,
  });

  @override
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.view != view ||
        oldDelegate.ratio != ratio ||
        oldDelegate.area != area ||
        oldDelegate.active != active;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _kCropHandleSize / 2,
      _kCropHandleSize / 2,
      size.width - _kCropHandleSize,
      size.height - _kCropHandleSize,
    );

    canvas.save();
    canvas.translate(rect.left, rect.top);

    final paint = Paint()..isAntiAlias = false;

    if (image != null) {
      final src = Rect.fromLTWH(
        0.0,
        0.0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromLTWH(
        view.left * image.width * ratio,
        view.top * image.height * ratio,
        image.width * ratio,
        image.height * ratio,
      );

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0.0, 0.0, rect.width, rect.height));
      canvas.drawImageRect(image, src, dst, paint);
      canvas.restore();
    }

    paint.color = _kCropOverlayColor;

    final boundaries = Rect.fromLTWH(
      rect.width * area.left,
      rect.height * area.top,
      rect.width * area.width,
      rect.height * area.height,
    );
    canvas.drawRect(Rect.fromLTRB(0.0, 0.0, rect.width, boundaries.top), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.bottom, rect.width, rect.height), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.top, boundaries.left, boundaries.bottom),
        paint);
    canvas.drawRect(
        Rect.fromLTRB(
            boundaries.right, boundaries.top, rect.width, boundaries.bottom),
        paint);

    if (!boundaries.isEmpty) {
      _drawBorder(canvas, boundaries);
      _drawGrid(canvas, boundaries);
      _drawHandles(canvas, boundaries);
    }

    canvas.restore();
  }

  void _drawBorder(Canvas canvas, Rect boundaries) {
    final paint = Paint()
      ..isAntiAlias = false
      ..color = _kCropBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(boundaries, paint);
  }

  void _drawHandles(Canvas canvas, Rect boundaries) {
    _ovalWithBorder(canvas, boundaries.topLeft);
    _ovalWithBorder(canvas, boundaries.topRight);
    _ovalWithBorder(canvas, boundaries.bottomLeft);
    _ovalWithBorder(canvas, boundaries.bottomRight);
  }

  void _ovalWithBorder(Canvas canvas, Offset center, {double radius = 5}) {
    Paint paintCircle = Paint()..color = Color.fromRGBO(0xd0, 0xd0, 0xd0, 1);

    Paint paintBorder = Paint()
      ..color = _kCropBorderColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, paintCircle);
    canvas.drawCircle(center, radius, paintBorder);
  }

  void _drawGrid(Canvas canvas, Rect boundaries) {
    if (active == 0.0) return;

    final paint = Paint()
      ..isAntiAlias = false
      ..color = _kCropGridColor.withOpacity(_kCropGridColor.opacity * active)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();

    for (var column = 1; column < _kCropGridColumnCount; column++) {
      path
        ..moveTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.top)
        ..lineTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.bottom);
    }

    for (var row = 1; row < _kCropGridRowCount; row++) {
      path
        ..moveTo(boundaries.left,
            boundaries.top + row * boundaries.height / _kCropGridRowCount)
        ..lineTo(boundaries.right,
            boundaries.top + row * boundaries.height / _kCropGridRowCount);
    }

    canvas.drawPath(path, paint);
  }
}
