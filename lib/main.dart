import 'dart:typed_data';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:wid_mage/wid_mage.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Markdown 渲染工具',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();

  final GlobalKey _previewKey = GlobalKey();
  final GlobalKey _tempTableKey = GlobalKey();
  Uint8List? _extractedTableImage;
  bool _isExtracting = false;
  List<String> _detectedTables = [];

  // ==================== ASCII 表格转换方法 ====================

  String _convertAsciiTableToMarkdown(String text) {
    final lines = text.split('\n');
    final result = <String>[];
    final asciiTableBuffer = <String>[];
    bool inAsciiTable = false;

    for (var line in lines) {
      final isAsciiTableLine = line.contains('┌') ||
          line.contains('┐') ||
          line.contains('└') ||
          line.contains('┘') ||
          line.contains('├') ||
          line.contains('┤') ||
          (line.contains('│') && line.contains('─'));

      if (isAsciiTableLine) {
        inAsciiTable = true;
        asciiTableBuffer.add(line);
      } else if (inAsciiTable && line.trim().isEmpty) {
        if (asciiTableBuffer.isNotEmpty) {
          result.add(_convertSingleAsciiTable(asciiTableBuffer));
          asciiTableBuffer.clear();
        }
        inAsciiTable = false;
        result.add(line);
      } else if (inAsciiTable) {
        asciiTableBuffer.add(line);
      } else {
        result.add(line);
      }
    }

    if (asciiTableBuffer.isNotEmpty) {
      result.add(_convertSingleAsciiTable(asciiTableBuffer));
    }

    return result.join('\n');
  }

  String _convertSingleAsciiTable(List<String> asciiLines) {
    final rows = <List<String>>[];

    for (var line in asciiLines) {
      if (line.contains('┌') ||
          line.contains('├') ||
          line.contains('└') ||
          line.contains('─')) {
        if (!line.contains('│') || line.replaceAll('│', '').trim().isEmpty) {
          continue;
        }
      }

      final cells = <String>[];
      final parts = line.split('│');
      for (int j = 1; j < parts.length - 1; j++) {
        String cell = parts[j].trim();
        cell = cell.replaceAll(RegExp(r'[─┌┐└┘├┤]'), '').trim();
        cells.add(cell.isEmpty ? ' ' : cell);
      }

      if (cells.isNotEmpty) {
        rows.add(cells);
      }
    }

    if (rows.isEmpty) {
      return asciiLines.join('\n');
    }

    final buffer = StringBuffer();
    buffer.write('| ${rows[0].join(' | ')} |\n');
    buffer.write(
        '| ${List.generate(rows[0].length, (_) => '---').join(' | ')} |\n');
    for (var i = 1; i < rows.length; i++) {
      buffer.write('| ${rows[i].join(' | ')} |\n');
    }

    return buffer.toString();
  }

  String _fixMarkdownTable(String markdown) {
    final lines = markdown.split('\n');
    final result = <String>[];
    bool inTable = false;
    int tableStartIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isTableLine = line.trim().startsWith('|') &&
          line.trim().endsWith('|') &&
          line.contains('|');

      if (isTableLine) {
        if (!inTable) {
          inTable = true;
          tableStartIndex = i;
        }
        result.add(line);
      } else {
        if (inTable && tableStartIndex >= 0) {
          final tableLines = result.sublist(tableStartIndex);
          if (tableLines.length >= 1) {
            bool hasSeparator = false;
            if (tableLines.length > 1) {
              hasSeparator = tableLines[1].contains('---');
            }
            if (!hasSeparator && tableLines.isNotEmpty) {
              final headerRow = tableLines[0];
              final columnCount = headerRow.split('|').length - 2;
              final separator =
                  '| ${List.generate(columnCount, (_) => '---').join(' | ')} |';
              result.insert(tableStartIndex + 1, separator);
            }
          }
          inTable = false;
          tableStartIndex = -1;
        }
        result.add(line);
      }
    }

    return result.join('\n');
  }

  List<String> _extractTablesFromMarkdown(String markdown) {
    final tables = <String>[];
    final lines = markdown.split('\n');
    final tableBuffer = <String>[];
    bool inTable = false;

    for (var line in lines) {
      final isTableLine = line.trim().startsWith('|') &&
          line.trim().endsWith('|') &&
          line.contains('|');

      if (isTableLine) {
        if (!inTable) {
          inTable = true;
          tableBuffer.clear();
        }
        tableBuffer.add(line);
      } else {
        if (inTable && tableBuffer.isNotEmpty) {
          tables.add(tableBuffer.join('\n'));
          inTable = false;
          tableBuffer.clear();
        }
      }
    }

    if (inTable && tableBuffer.isNotEmpty) {
      tables.add(tableBuffer.join('\n'));
    }

    return tables;
  }

  String _markdownToHtml(String markdown) {
    final htmlContent = md.markdownToHtml(
      markdown,
      inlineSyntaxes: [md.EmojiSyntax()],
      extensionSet: md.ExtensionSet.gitHubWeb,
    );

    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; font-size: 12pt; margin: 0; padding: 10px; }
  table { border-collapse: collapse; width: 100%; margin: 10px 0; }
  th, td { border: 1px solid #aaa; padding: 8px; }
  th { background: #f0f0f0; font-weight: bold; }
  code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-family: 'Consolas', monospace; }
  pre { background: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; }
</style>
</head>
<body>
$htmlContent
</body>
</html>
''';
  }

  // ==================== 导出 Word ====================

  Future<void> _exportToWord() async {
    var markdown = _controller.text;
    if (markdown.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("请先粘贴 Markdown 内容")),
      );
      return;
    }

    markdown = _convertAsciiTableToMarkdown(markdown);
    markdown = _fixMarkdownTable(markdown);
    final htmlContent = _markdownToHtml(markdown);

    final blob = html.Blob([htmlContent], 'application/msword');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'document.doc')
      ..click();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Word 文档已下载！")),
      );
    }
  }

  // ==================== 保存图片 ====================

  Future<void> _saveImageToGallery(
      Uint8List imageBytes, String filename) async {
    final blob = html.Blob([imageBytes], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  // ==================== 提取表格为图片 ====================

  Future<void> _extractAndCaptureTable() async {
    if (_isExtracting) return;
    setState(() => _isExtracting = true);

    try {
      var markdown = _controller.text;
      if (markdown.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("请先粘贴 Markdown 内容")),
        );
        setState(() => _isExtracting = false);
        return;
      }

      markdown = _convertAsciiTableToMarkdown(markdown);
      _detectedTables = _extractTablesFromMarkdown(markdown);

      if (_detectedTables.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("未检测到表格，请确保内容中包含 Markdown 表格")),
          );
        }
        setState(() => _isExtracting = false);
        return;
      }

      if (_detectedTables.length == 1) {
        await _showTableCaptureDialog(_detectedTables[0], 0);
      } else {
        await _showTableSelectionDialog();
      }
    } catch (e) {
      debugPrint("提取表格失败: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("提取表格失败")),
        );
      }
    } finally {
      setState(() => _isExtracting = false);
    }
  }

  Future<void> _showTableSelectionDialog() async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("选择要提取的表格"),
        content: SizedBox(
          width: 300,
          height: 200,
          child: ListView.builder(
            itemCount: _detectedTables.length,
            itemBuilder: (ctx, index) {
              final lines = _detectedTables[index].split('\n');
              final preview = lines.isNotEmpty
                  ? lines[0].substring(0, lines[0].length.clamp(0, 50))
                  : '表格 ${index + 1}';
              return ListTile(
                title: Text('表格 ${index + 1}'),
                subtitle: Text(preview),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _showTableCaptureDialog(_detectedTables[index], index);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("取消"),
          ),
        ],
      ),
    );
  }

  Future<void> _showTableCaptureDialog(String tableMarkdown, int index) async {
    final rowCount = tableMarkdown.split('\n').length;
    final dialogHeight = (rowCount * 40 + 120).clamp(200, 500);

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('表格 ${index + 1} 预览'),
        content: SizedBox(
          width: 600,
          height: dialogHeight.toDouble(),
          child: SingleChildScrollView(
            child: RepaintBoundary(
              key: _tempTableKey,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: MarkdownBody(
                  data: tableMarkdown,
                  selectable: false,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final image = await WidMageController.onCaptureImage(
                  globalKey: _tempTableKey,
                );
                if (image != null) {
                  setState(() => _extractedTableImage = image);
                  await _saveImageToGallery(image, 'table_${index + 1}.png');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("表格 ${index + 1} 已保存！")),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("截图失败")),
                    );
                  }
                }
              } catch (e) {
                debugPrint("保存失败: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("保存失败: $e")),
                  );
                }
              }
              Navigator.pop(dialogContext);
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  // ==================== 界面构建 ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Markdown 渲染器")),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // 输入框
            Expanded(
              flex: 1,
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  hintText:
                      "在这里粘贴 Markdown 内容...\n\n示例：\n# 标题\n**加粗文字**\n\n| 列1 | 列2 |\n| --- | --- |\n| 数据1 | 数据2 |",
                  hintMaxLines: 8,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 按钮栏
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.preview),
                  label: const Text("刷新预览"),
                ),
                ElevatedButton.icon(
                  onPressed: _exportToWord,
                  icon: const Icon(Icons.file_download),
                  label: const Text("导出 Word"),
                ),
                ElevatedButton.icon(
                  onPressed: _extractAndCaptureTable,
                  icon: _isExtracting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.table_chart),
                  label: const Text("提取表格为图片"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 建议提示框
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb, size: 20, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "💡 推荐使用 Microsoft Word 打开导出的文件，格式显示最佳",
                      style:
                          TextStyle(fontSize: 12, color: Colors.blue.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 预览区
            Expanded(
              flex: 2,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("✨ 实时预览",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Divider(),
                      Expanded(
                        child: RepaintBoundary(
                          key: _previewKey,
                          child: SingleChildScrollView(
                            child: MarkdownBody(
                              data: _controller.text,
                              selectable: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
