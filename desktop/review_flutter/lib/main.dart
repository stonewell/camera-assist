import 'package:flutter/material.dart';

void main() {
  runApp(const ReviewFlutterApp());
}

/// Desktop Flutter application for batch photo review, culling, and auto-fix previews.
class ReviewFlutterApp extends StatelessWidget {
  const ReviewFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera Assist Desktop Review',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD60A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ReviewWorkspacePage(),
    );
  }
}

enum FilterChipMode { all, fixable, good, culled }

class PhotoItem {
  final String id;
  final String filename;
  final int originalScore;
  int score;
  bool isCulled;
  bool isFixed;
  final double? suggestedStraightenDeg;
  final String? defectDescription;

  PhotoItem({
    required this.id,
    required this.filename,
    required this.score,
    int? originalScore,
    this.isCulled = false,
    this.isFixed = false,
    this.suggestedStraightenDeg,
    this.defectDescription,
  }) : originalScore = originalScore ?? score;

  bool get isFixable => suggestedStraightenDeg != null;
  bool get isGood => score >= 80 && !isCulled;
}

/// Main desktop review workspace page featuring virtualized GridView.builder,
/// batch action toolbar, filter chips, and interactive BeforeAfterComparisonView.
class ReviewWorkspacePage extends StatefulWidget {
  const ReviewWorkspacePage({super.key});

  @override
  State<ReviewWorkspacePage> createState() => _ReviewWorkspacePageState();
}

class _ReviewWorkspacePageState extends State<ReviewWorkspacePage> {
  FilterChipMode _activeFilter = FilterChipMode.all;
  PhotoItem? _selectedPhoto;

  final List<PhotoItem> _photos = List.generate(
    24,
    (index) => PhotoItem(
      id: 'IMG_${1000 + index}',
      filename: 'IMG_${1000 + index}.JPG',
      score: (index % 4 == 0)
          ? 55
          : (index % 3 == 0)
              ? 70
              : 92,
      suggestedStraightenDeg: (index % 2 == 0) ? -3.5 : null,
      defectDescription: (index % 2 == 0) ? '地平线顺时针歪斜 3.5°' : null,
    ),
  );

  List<PhotoItem> get _filteredPhotos {
    switch (_activeFilter) {
      case FilterChipMode.all:
        return _photos;
      case FilterChipMode.fixable:
        return _photos.where((p) => p.isFixable && !p.isCulled).toList();
      case FilterChipMode.good:
        return _photos.where((p) => p.isGood && !p.isCulled).toList();
      case FilterChipMode.culled:
        return _photos.where((p) => p.isCulled).toList();
    }
  }

  void _batchApplyAllAutoFixes() {
    setState(() {
      for (final p in _photos) {
        if (p.isFixable && !p.isCulled && !p.isFixed) {
          p.isFixed = true;
          p.score = (p.originalScore + 20).clamp(0, 100);
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已批量应用废片拯救智能构图修复！')),
    );
  }

  void _undoAllFixes() {
    setState(() {
      for (final p in _photos) {
        if (p.isFixed) {
          p.isFixed = false;
          p.score = p.originalScore;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('相册智能审片与废片拯救工作区 (Desktop)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: '撤销调整',
            onPressed: _undoAllFixes,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('一键拯救所有废片'),
            onPressed: _batchApplyAllAutoFixes,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // Left: Filter & Grid View
          Expanded(
            flex: 6,
            child: Column(
              children: [
                _buildFilterChips(),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 0.9,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _filteredPhotos.length,
                    itemBuilder: (context, index) {
                      final photo = _filteredPhotos[index];
                      final isSelected = _selectedPhoto?.id == photo.id;

                      return Card(
                        elevation: isSelected ? 4 : 1,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFFFFD60A)
                                : photo.isFixed
                                    ? Colors.green
                                    : Colors.transparent,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: InkWell(
                          onTap: () => setState(() => _selectedPhoto = photo),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  photo.isCulled
                                      ? Icons.delete_outline
                                      : Icons.photo,
                                  size: 40,
                                  color: photo.isCulled
                                      ? Colors.red
                                      : Colors.white70,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  photo.filename,
                                  style: const TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${photo.score} 分',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: photo.score >= 80
                                        ? Colors.greenAccent
                                        : Colors.amberAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right: Detail & Before/After Comparison Inspector
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.black26,
              padding: const EdgeInsets.all(16),
              child: _selectedPhoto == null
                  ? const Center(child: Text('请在相册网格中选择照片查看构图缺陷与拯救预览'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _selectedPhoto!.filename,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedPhoto!.defectDescription ?? '构图优秀，无需修复',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: BeforeAfterComparisonView(
                            photo: _selectedPhoto!,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              icon: Icon(_selectedPhoto!.isCulled
                                  ? Icons.restore
                                  : Icons.delete),
                              label: Text(_selectedPhoto!.isCulled
                                  ? '取消标记'
                                  : '标记剔除'),
                              onPressed: () {
                                setState(() {
                                  _selectedPhoto!.isCulled =
                                      !_selectedPhoto!.isCulled;
                                });
                              },
                            ),
                            const Spacer(),
                            if (_selectedPhoto!.isFixable)
                              FilledButton.icon(
                                icon: const Icon(Icons.auto_fix_normal),
                                label: Text(_selectedPhoto!.isFixed
                                    ? '重新应用修复'
                                    : '应用废片拯救'),
                                onPressed: () {
                                  setState(() {
                                    _selectedPhoto!.isFixed = true;
                                    _selectedPhoto!.score = (_selectedPhoto!.originalScore + 20).clamp(0, 100);
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('全部'),
            selected: _activeFilter == FilterChipMode.all,
            onSelected: (_) =>
                setState(() => _activeFilter = FilterChipMode.all),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('待修复'),
            selected: _activeFilter == FilterChipMode.fixable,
            onSelected: (_) =>
                setState(() => _activeFilter = FilterChipMode.fixable),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('构图良好'),
            selected: _activeFilter == FilterChipMode.good,
            onSelected: (_) =>
                setState(() => _activeFilter = FilterChipMode.good),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('已剔除'),
            selected: _activeFilter == FilterChipMode.culled,
            onSelected: (_) =>
                setState(() => _activeFilter = FilterChipMode.culled),
          ),
        ],
      ),
    );
  }
}

/// Before-and-after interactive slider view showing original vs straightened/cropped preview.
class BeforeAfterComparisonView extends StatefulWidget {
  final PhotoItem photo;

  const BeforeAfterComparisonView({super.key, required this.photo});

  @override
  State<BeforeAfterComparisonView> createState() =>
      _BeforeAfterComparisonViewState();
}

class _BeforeAfterComparisonViewState extends State<BeforeAfterComparisonView> {
  double _splitRatio = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final splitX = constraints.maxWidth * _splitRatio;

        return Stack(
          children: [
            // Before: Original
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('原图 (Before: 歪斜/构图不佳)',
                    style: TextStyle(color: Colors.white54)),
              ),
            ),

            // After: Auto-fixed & cropped
            ClipRect(
              clipper: _HorizontalSplitClipper(splitX),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text('拯救后 (After: 自动旋转裁剪)',
                      style: TextStyle(
                          color: Color(0xFFFFD60A),
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),

            // Divider draggable handle
            Positioned(
              left: splitX - 10,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _splitRatio = (_splitRatio + details.delta.dx / constraints.maxWidth)
                        .clamp(0.05, 0.95);
                  });
                },
                child: Container(
                  width: 20,
                  alignment: Alignment.center,
                  child: Container(
                    width: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HorizontalSplitClipper extends CustomClipper<Rect> {
  final double splitX;

  _HorizontalSplitClipper(this.splitX);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(splitX, 0, size.width, size.height);
  }

  @override
  bool shouldReclip(_HorizontalSplitClipper oldClipper) =>
      oldClipper.splitX != splitX;
}
