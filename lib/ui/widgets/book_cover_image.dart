import 'package:flutter/material.dart';

/// 书籍封面：有网图就用网图，失败/缺失时退回「首字 + 稳定色」占位。
///
/// 本地导入的书没有封面，在线导入的有；用同一个组件让书架与探索页
/// 视觉一致，也避免在线源的图挂掉时出现空白块。
class BookCoverImage extends StatelessWidget {
  const BookCoverImage({
    super.key,
    required this.title,
    this.coverUrl = '',
    this.width,
    this.height,
    this.radius = 6,
    this.fontSize = 42,
  });

  final String title;
  final String coverUrl;
  final double? width;
  final double? height;
  final double radius;
  final double fontSize;

  static const List<Color> _colors = <Color>[
    Color(0xFF8D6E63),
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF9A9A),
    Color(0xFF9575CD),
    Color(0xFF4DB6AC),
  ];

  @override
  Widget build(BuildContext context) {
    final Widget fallback = _placeholder();

    if (coverUrl.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        coverUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) => fallback,
        loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? progress) {
          if (progress == null) {
            return child;
          }
          return Container(
            width: width,
            height: height,
            color: Colors.black12,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _placeholder() {
    final int index = title.isEmpty ? 0 : title.codeUnits.first % _colors.length;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colors[index],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        title.isEmpty ? '书' : title.characters.first,
        style: TextStyle(fontSize: fontSize, color: Colors.white70),
      ),
    );
  }
}
