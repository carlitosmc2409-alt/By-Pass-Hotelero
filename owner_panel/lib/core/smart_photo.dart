import 'dart:convert';
import 'package:flutter/material.dart';
import 'owner_theme.dart';

/// Renderiza una fotografía del hotel o suite admitiendo tanto URLs HTTP/HTTPS
/// como imágenes locales subidas por el propietario en `data:image/...;base64,...`.
class SmartPhoto extends StatelessWidget {
  final String? source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;

  const SmartPhoto({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final src = source?.trim() ?? '';
    Widget content;

    if (src.isEmpty) {
      content = _buildFallback();
    } else if (src.startsWith('data:image')) {
      final commaIdx = src.indexOf('base64,');
      if (commaIdx != -1) {
        try {
          final bytes = base64Decode(src.substring(commaIdx + 7));
          content = Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => _buildFallback(),
          );
        } on Object {
          content = _buildFallback();
        }
      } else {
        content = _buildFallback();
      }
    } else {
      content = Image.network(
        src,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }
    return content;
  }

  Widget _buildFallback() {
    if (fallback != null) return fallback!;
    return Container(
      width: width,
      height: height,
      color: OwnerTheme.surface,
      child: Center(
        child: Icon(
          Icons.add_a_photo_outlined,
          color: OwnerTheme.textSecondary,
          size: 26,
        ),
      ),
    );
  }
}
