/// 商品画像。サーバーから認証付きで取得し、メモリに保持する（取得できなければ何も表示しない）。
library;

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:onlipos/api/pos_api_client.dart';
import 'package:onlipos/product/product.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.product, this.size = 48});

  final Product product;
  final double size;

  static const _maxEntries = 300;
  static final Map<int, Future<Uint8List?>> _cache = {};

  static Future<Uint8List?> _fetch(int productId) async {
    try {
      final response = await PosApiClient.send(
        'GET',
        '/api/v1/products/$productId/image',
      );
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = product.imageVersion;
    if (version == null) return const SizedBox.shrink();
    if (_cache.length > _maxEntries) _cache.clear();
    return FutureBuilder<Uint8List?>(
      future: _cache[version] ??= _fetch(product.id),
      builder: (context, snapshot) => snapshot.data == null
          ? SizedBox(width: size, height: size)
          : Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 2).round(),
              errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
            ),
    );
  }
}
