import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/theme/app_colors.dart';

class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({super.key, required this.path, required this.title});

  final String path;
  final String title;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  final PdfViewerController _controller = PdfViewerController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Zoom in',
            onPressed: () => _controller.zoomUp(),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: () => _controller.zoomDown(),
            icon: const Icon(Icons.remove),
          ),
        ],
      ),
      body: ColoredBox(
        color: AppColors.lightSurfaceVariant,
        child: PdfViewer.file(
          widget.path,
          controller: _controller,
          params: const PdfViewerParams(
            backgroundColor: Color(0xFFF1F5F9),
            margin: 8.0,
            panAxis: PanAxis.free,
          ),
        ),
      ),
    );
  }
}
