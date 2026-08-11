/// POP(値札)印刷用のPDFを組み立てるビルダー。1ページあたりの面付け数(1/2/4/8/16)に
/// 応じてグリッドを敷き、各セルに商品名・税込/税抜価格・バーコードを描画する。
library;

import 'dart:typed_data';
import 'package:barcode/barcode.dart' as bc;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:onlipos/product/product.dart';

/// POP印刷リストの1エントリ(商品と印刷枚数)
class PopItem {
  final Product product;
  int count;

  PopItem({required this.product, this.count = 1});
}

// A4 1ページに何面配置するかに対応するグリッド設定
const _kGrid = <int, ({int rows, int cols})>{
  1: (rows: 1, cols: 1),
  2: (rows: 2, cols: 1),
  4: (rows: 2, cols: 2),
  8: (rows: 4, cols: 2),
  16: (rows: 4, cols: 4),
};

class PopPdfBuilder {
  /// 純粋なページ数計算（テスト可能・ネットワーク不要）
  static int pageCount(List<PopItem> items, int perPage) {
    final total = items.fold(0, (sum, e) => sum + e.count);
    if (total == 0) return 0;
    return (total / perPage).ceil();
  }

  /// 商品リストと面付け数からPOP用PDFを生成する
  static Future<Uint8List> build(List<PopItem> items, int perPage) async {
    final cfg = _kGrid[perPage]!;

    final font = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();

    final doc = pw.Document();
    const fmt = PdfPageFormat.a4;

    // 商品を指定枚数だけ展開してセルリストを作る
    final cells = <Product>[];
    for (final item in items) {
      for (var i = 0; i < item.count; i++) {
        cells.add(item.product);
      }
    }
    if (cells.isEmpty) return doc.save();

    final cellW = fmt.width / cfg.cols;
    final cellH = fmt.height / cfg.rows;

    var idx = 0;
    while (idx < cells.length) {
      final pageCells = cells.skip(idx).take(perPage).toList();
      idx += perPage;

      doc.addPage(
        pw.Page(
          pageFormat: fmt,
          margin: pw.EdgeInsets.zero,
          build: (_) {
            final rowWidgets = <pw.Widget>[];
            for (var r = 0; r < cfg.rows; r++) {
              final colWidgets = <pw.Widget>[];
              for (var c = 0; c < cfg.cols; c++) {
                final i = r * cfg.cols + c;
                if (i < pageCells.length) {
                  colWidgets.add(
                    _buildCell(pageCells[i], cellW, cellH, font, bold),
                  );
                } else {
                  colWidgets.add(pw.SizedBox(width: cellW, height: cellH));
                }
              }
              rowWidgets.add(pw.Row(children: colWidgets));
            }
            return pw.Column(children: rowWidgets);
          },
        ),
      );
    }

    return doc.save();
  }

  // 1商品分のPOPセル(商品名・価格・バーコード・説明文)を描画する
  static pw.Widget _buildCell(
    Product p,
    double cellW,
    double cellH,
    pw.Font font,
    pw.Font bold,
  ) {
    final pad = (cellW * 0.04).clamp(2.0, 12.0);
    final nameFs = (cellH * 0.09).clamp(7.0, 32.0);
    final priceFs = (cellH * 0.13).clamp(8.0, 44.0);
    final subFs = (cellH * 0.06).clamp(5.5, 16.0);
    final descFs = (cellH * 0.05).clamp(5.0, 11.0);
    final barcodeH = (cellH * 0.20).clamp(18.0, 70.0);

    final taxIncl = p.price;
    final taxExcl = (taxIncl * 100 / (100 + p.taxRate)).floor();

    // バーコードウィジェット（例外は無視して描画しない）
    pw.Widget? barcodeWidget;
    if (p.code.isNotEmpty) {
      try {
        final barcodeType = _isValidEan13(p.code)
            ? bc.Barcode.ean13()
            : bc.Barcode.code128();
        barcodeWidget = pw.Center(
          child: pw.BarcodeWidget(
            barcode: barcodeType,
            data: p.code,
            width: (cellW - pad * 2) * 0.85,
            height: barcodeH,
            textStyle: pw.TextStyle(
              font: font,
              fontSize: (descFs * 0.8).clamp(4.5, 9.0),
            ),
          ),
        );
      } catch (_) {
        barcodeWidget = null;
      }
    }

    final children = <pw.Widget>[
      // 商品名（太字・大）
      pw.Text(
        p.name,
        style: pw.TextStyle(font: bold, fontSize: nameFs),
        maxLines: 2,
        overflow: pw.TextOverflow.clip,
      ),
      pw.SizedBox(height: pad * 0.4),
      // 税込価格（大）
      pw.Text(
        '¥${_fmt(taxIncl)}（税込）',
        style: pw.TextStyle(font: bold, fontSize: priceFs),
      ),
      // 税抜価格（小・グレー）
      pw.Text(
        '¥${_fmt(taxExcl)}（税抜・${p.taxRate}%）',
        style: pw.TextStyle(
          font: font,
          fontSize: subFs,
          color: PdfColors.grey600,
        ),
      ),
      if (barcodeWidget != null) ...[
        pw.SizedBox(height: pad * 0.5),
        barcodeWidget,
      ],
      if (p.description != null && p.description!.isNotEmpty) ...[
        pw.SizedBox(height: pad * 0.3),
        pw.Text(
          p.description!,
          style: pw.TextStyle(
            font: font,
            fontSize: descFs,
            color: PdfColors.grey700,
          ),
          maxLines: 3,
          overflow: pw.TextOverflow.clip,
        ),
      ],
    ];

    return pw.Container(
      width: cellW,
      height: cellH,
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300),
          right: pw.BorderSide(color: PdfColors.grey300),
        ),
      ),
      padding: pw.EdgeInsets.all(pad),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // EAN-13 チェックデジット検証
  static bool _isValidEan13(String code) {
    if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(code[i]) * (i.isEven ? 1 : 3);
    }
    return (10 - (sum % 10)) % 10 == int.parse(code[12]);
  }

  // 金額を3桁区切りのカンマ付き文字列に整形する
  static String _fmt(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}
